import Foundation
import SwiftOBD2
import Combine
import os.log
import CoreBluetooth

@MainActor
class OBDConnectionManager: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(Error) // Using String for simple Equatable conformance

        static func == (lhs: OBDConnectionManager.ConnectionState, rhs: OBDConnectionManager.ConnectionState) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected):
                return true
            case (.connecting, .connecting):
                return true
            case (.connected, .connected):
                return true
            case let (.failed(lError), .failed(rError)):
                return lError.localizedDescription == rError.localizedDescription
            default:
                return false
            }
        }
    }

    private let querySupportedPids = true
    private var supportedPids: [OBDCommand] = []
    
    static let shared = OBDConnectionManager()
    //private let logger = Logger(subsystem: "com.rheosoft.obdii", category: "OBDConnection")

    @Published var connectionState: ConnectionState = .disconnected
    @Published var troubleCodes: [TroubleCodeMetadata]  = []
    
    @Published var fuelStatus: [StatusCodeMetadata?] = []
    @Published var MILStatus: Status?

    
    // New: publish the connected peripheral name (Bluetooth), or nil for Wi‑Fi/Demo/none
    @Published var connectedPeripheralName: String?

    struct PIDStats: Equatable {
        private static let logger = Logger(subsystem: "com.rheosoft.obdii", category: "OBDConnection.PIDStats")

        var pid: OBDCommand
        var latest: MeasurementResult
        var min: Double
        var max: Double
        var sampleCount: Int

        init(pid: OBDCommand, measurement: MeasurementResult) {
            self.pid = pid
            self.latest = measurement
            self.min = measurement.value
            self.max = measurement.value
            self.sampleCount = 1
        }

        mutating func update(with measurement: MeasurementResult) {
            let value = measurement.value
            latest = measurement
            if value < min { min = value }
            if value > max { max = value }
            sampleCount &+= 1
        }
    }

    @Published private(set) var pidStats: [OBDCommand: PIDStats] = [:]

    private var obdService: OBDService
    private var cancellables = Set<AnyCancellable>()           // general subscriptions (mirror, config, etc.)
    private var streamCancellables = Set<AnyCancellable>()     // continuous updates stream only
    private var pidStoreCancellable: AnyCancellable?

    // Track the last set of PIDs we actually started streaming
    private var lastStreamingPIDs: Set<OBDCommand> = []

    private init() {
        self.obdService = OBDService(
            connectionType: ConfigData.shared.connectionType,
            host: ConfigData.shared.wifiHost,
            port: UInt16(ConfigData.shared.wifiPort)
        )

        // Mirror the connected peripheral name from OBDService
        obdService.$connectedPeripheral
            .map { $0?.name }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in
                self?.connectedPeripheralName = name
            }
            .store(in: &cancellables)

        // Mirror OBDService connection state to local state via helper
        obdService.$connectionState
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] serviceState in
                self?.handleServiceConnectionState(serviceState)
            }
            .store(in: &cancellables)

        // Observe changes to enabled PIDs and restart streaming if connected.
        // Debounce to avoid flapping on view renders; use Set to ignore order changes.
        pidStoreCancellable = PIDStore.shared.$pids
            .map { pids -> Set<OBDCommand> in
                Set(pids.filter { $0.enabled }.map { $0.pid })
            }
            //.debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] enabledSet in
                guard let self else { return }

                // Prune pidStats for any PIDs that are no longer enabled
                if !self.pidStats.isEmpty {
                    let before = self.pidStats.count
                    self.pidStats = self.pidStats.filter { enabledSet.contains($0.key) }
                    let after = self.pidStats.count
                    if before != after {
                        obdInfo("Pruned disabled PIDs from pidStats: \(before - after) removed.", category: .service)
                    }
                }

                // Only restart if connected; equality/no-change is handled inside restart/start
                if self.connectionState == .connected {
                    obdInfo("Enabled PID set changed (\(enabledSet.count)); requesting restart of continuous updates.", category: .service)
                    self.restartContinuousUpdates(with: enabledSet)
                }
            }

        // NEW: Observe units changes and restart stream in the new unit, resetting stats to avoid mixed units
        ConfigData.shared.$unitsPublished
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                // Compute current enabled set (after any support filtering will happen in startContinuousOBDUpdates)
                let enabledSet = Set(PIDStore.shared.pids.filter { $0.enabled }.map { $0.pid })
                if self.connectionState == .connected {
                    obdInfo("Units changed to \(ConfigData.shared.units.rawValue); restarting continuous updates and resetting stats.", category: .service)
                    self.resetAllStats()
                    // clear this so we reset the units
                    lastStreamingPIDs = []
                    self.restartContinuousUpdates(with: enabledSet)
                } else {
                    // If not connected, just clear stats so next connection starts fresh
                    self.resetAllStats()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - State mapping helpers

    private func clearForTerminalState() {
        streamCancellables.removeAll()
        lastStreamingPIDs = []
        pidStats.removeAll()
        fuelStatus = []
        MILStatus = nil
        troubleCodes = []
        connectedPeripheralName = nil
    }

    private func handleServiceConnectionState(_ serviceState: SwiftOBD2.ConnectionState) {
        switch serviceState {
        case .disconnected:
            clearForTerminalState()
            connectionState = .disconnected
            obdDebug("Mirrored service disconnect to manager state and cleared data.", category: .service)
        case .error:
            clearForTerminalState()
            let err = OBDServiceError.notConnectedToVehicle
            connectionState = .failed(err)
            obdError("Service reported error \(err); mapped to .failed and cleared data.", category: .service)
        case .connecting:
            if connectionState != .connecting {
                connectionState = .connecting
            }
        case .connectedToAdapter, .connectedToVehicle:
            if connectionState != .connected {
                connectionState = .connected
            }
        }
    }

    func updateConnectionDetails() {
        if connectionState != .disconnected {
            disconnect()
        }
        self.obdService = OBDService(
            connectionType: ConfigData.shared.connectionType,
            host: ConfigData.shared.wifiHost,
            port: UInt16(ConfigData.shared.wifiPort)
        )
        // Re-bind to the new service’s connectedPeripheral
        obdService.$connectedPeripheral
            .map { $0?.name }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in
                self?.connectedPeripheralName = name
            }
            .store(in: &cancellables)

        // Re-bind to the new service’s connectionState via helper
        obdService.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] serviceState in
                self?.handleServiceConnectionState(serviceState)
            }
            .store(in: &cancellables)

        obdInfo("OBD Service re-initialized with new settings.", category: .service)
    }

    func connect() async {
        guard connectionState == .disconnected || connectionState.isFailed else {
            // logger.warning(...) was here; using info to avoid dependency on Logger
            obdWarning("Connection attempt ignored, already connected or connecting.", category: .service)
            return
        }

        connectionState = .connecting

        do {
            _ = try await obdService.startConnection(preferedProtocol: .protocol6, timeout: 30, querySupportedPIDs: querySupportedPids)
            
            supportedPids = await obdService.getSupportedPIDs()
            
            
            let myTroubleCodes = try await obdService.scanForTroubleCodes()
            if (myTroubleCodes[SwiftOBD2.ECUID.engine] != nil) {
                troubleCodes = myTroubleCodes[SwiftOBD2.ECUID.engine]!
            }
            connectionState = .connected
            // Set name immediately if available (Bluetooth). For Wi‑Fi/Demo, this remains nil.
            connectedPeripheralName = obdService.connectedPeripheral?.name
            obdInfo("OBD-II connected successfully.", category: .service)
            startContinuousOBDUpdates()
        } catch {
            let errorMessage = error.localizedDescription
            connectionState = .failed(error)
            connectedPeripheralName = nil
            obdError("OBD-II connection failed: \(errorMessage)", category: .service)
        }
    }

    func disconnect() {
        // Stop the stream cleanly
         obdService.stopConnection()

        // Keep general cancellables (like mirror) active or clear? We’ll clear them too on full disconnect.
        cancellables.removeAll()
        
        // clear all the published stuff
        clearForTerminalState()
       
        connectionState = .disconnected
        obdInfo("OBD-II disconnected.", category: .service)
    }

    private func resetAllStats() {
        pidStats = pidStats.mapValues { existing in
            var reset = existing
            reset.min = existing.latest.value
            reset.max = existing.latest.value
            reset.sampleCount = 1
            return reset
        }
        obdInfo("All PID stats reset (min/max/sampleCount).", category: .service)
    }

    private func resetStats(for pid: OBDCommand) {
        guard var existing = pidStats[pid] else { return }
        existing.min = existing.latest.value
        existing.max = existing.latest.value
        existing.sampleCount = 1
        pidStats[pid] = existing
        obdInfo("PID stats reset for \(String(describing: pid)).", category: .service)
    }

    func stats(for pid: OBDCommand) -> PIDStats? {
        pidStats[pid]
    }

    private func startContinuousOBDUpdates() {
        // Build commands from the current enabled PIDs in the store.
        // If you want only gauges, use enabledGauges; otherwise include all enabled items.
        let enabledNow = Set(PIDStore.shared.pids.filter { $0.enabled }.map { $0.pid })

        startContinuousOBDUpdates(with: enabledNow)
    }

    private func startContinuousOBDUpdates(with enabledPIDs: Set<OBDCommand>) {
        // Only rebuild the stream if the set differs
        var enabledNow = enabledPIDs
        if querySupportedPids {
            // Build the supported Mode 01 set
            let supportedMode1: Set<OBDCommand> = Set(
                supportedPids.compactMap { cmd in
                    if case let .mode1(m) = cmd { return .mode1(m) }
                    return nil
                }
            )

            // Keep all non-mode1; for mode1 keep only those present in supportedMode1
            let filtered: Set<OBDCommand> = Set(enabledPIDs.filter { cmd in
                switch cmd {
                case .mode1:
                    return supportedMode1.contains(cmd)
                default:
                    return true
                }
            })

            // Compute and log removed (unsupported) items among mode1
            let removed = enabledPIDs.subtracting(filtered)
            if !removed.isEmpty {
                obdDebug("removing unsupported mode1 pids: \(removed)")
            }

            enabledNow = filtered
        }

        // Skip if no commands
        guard !enabledNow.isEmpty else {
            obdInfo("No enabled PIDs to monitor.", category: .service)
            // Clear stream if we previously had some
            if !lastStreamingPIDs.isEmpty {
                streamCancellables.removeAll()
                lastStreamingPIDs = []
            }
            return
        }

        // Skip if nothing changed
        if enabledNow == lastStreamingPIDs {
            obdInfo("Enabled PIDs unchanged; not restarting continuous updates.", category: .service)
            return
        }

        // Prune pidStats to only those still enabled (after support filtering)
        if !pidStats.isEmpty {
            let before = pidStats.count
            pidStats = pidStats.filter { enabledNow.contains($0.key) }
            let after = pidStats.count
            if before != after {
                obdInfo("Pruned disabled/unsupported PIDs from pidStats: \(before - after) removed.", category: .service)
            }
        }

        // Replace only the stream subscription
        streamCancellables.removeAll()

        let commands: [OBDCommand] = Array(enabledNow)
        lastStreamingPIDs = enabledNow

        obdInfo("Starting continuous updates for \(commands.count) PIDs.", category: .service)
        obdService
            .startContinuousUpdates(commands, unit: ConfigData.shared.units, interval: 1)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        obdError("Continuous OBD updates failed: \(error.localizedDescription)", category: .service)
                    }
                },
                receiveValue: { [weak self] measurements in
                    guard let self else { return }
                    for (command, decode) in measurements {
                        // Allow Mode 01 and GM Mode 22 commands through
                        switch command {
                        case .mode1(let pid):
                            switch pid {
                            case .fuelStatus:
                                self.fuelStatus = decode.codeResult!
                            case .status:
                                self.MILStatus = decode.statusResult!
                            default:
                                if let measurement = decode.measurementResult {
                                    let key: OBDCommand = .mode1(pid)
                                    var stats = self.pidStats[key] ?? PIDStats(pid: key, measurement: measurement)
                                    stats.update(with: measurement)
                                    self.pidStats[key] = stats
                                }
                            }
                        case .GMmode22:
                            // Treat GM Mode 22 as general measurements for stats
                            if let measurement = decode.measurementResult {
                                let key: OBDCommand = command
                                var stats = self.pidStats[key] ?? PIDStats(pid: key, measurement: measurement)
                                stats.update(with: measurement)
                                self.pidStats[key] = stats
                            }
                        default:
                            // Ignore other modes here unless needed
                            continue
                        }
                    }
                }
            )
            .store(in: &streamCancellables)
    }

    private func restartContinuousUpdates(with enabledPIDs: Set<OBDCommand>) {
        // Skip if no change vs current stream
        if enabledPIDs == lastStreamingPIDs {
            // Even if the set is the same, we still want to rebuild the stream if units changed,
            // but this function is only called when we know we need to (e.g., units change handler).
            // So force a rebuild by clearing lastStreamingPIDs here if needed by caller.
            obdInfo("Enabled PIDs unchanged; not restarting continuous updates.", category: .service)
        }
        // Force a rebuild by clearing and then starting fresh
        streamCancellables.removeAll()
        lastStreamingPIDs = []
        startContinuousOBDUpdates(with: enabledPIDs)
    }
}

extension OBDConnectionManager.ConnectionState {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

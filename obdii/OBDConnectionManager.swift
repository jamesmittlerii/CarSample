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

    let querySupportedPids = true
    var supportedPids: [OBDCommand] = []
    
    static let shared = OBDConnectionManager()
    private let logger = Logger(subsystem: "com.rheosoft.obdii", category: "OBDConnection")

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
    private var cancellables = Set<AnyCancellable>()
    private var pidStoreCancellable: AnyCancellable?

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

        // Observe changes to enabled PIDs and restart streaming if connected.
        // Use Set for removeDuplicates to avoid order-based suppression,
        // and pass the new enabled set into restart so we don't re-read stale state.
        pidStoreCancellable = PIDStore.shared.$pids
            .map { pids -> Set<OBDCommand> in
                Set(pids.filter { $0.enabled }.map { $0.pid })
            }
            .removeDuplicates()
            .sink { [weak self] enabledSet in
                guard let self else { return }

                // Prune pidStats for any PIDs that are no longer enabled
                if !self.pidStats.isEmpty {
                    let before = self.pidStats.count
                    self.pidStats = self.pidStats.filter { enabledSet.contains($0.key) }
                    let after = self.pidStats.count
                    if before != after {
                        self.logger.info("Pruned disabled PIDs from pidStats: \(before - after) removed.")
                    }
                }

                if self.connectionState == .connected {
                    self.logger.info("Enabled PID set changed (\(enabledSet.count)); restarting continuous updates.")
                    self.restartContinuousUpdates(with: enabledSet)
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

        logger.info("OBD Service re-initialized with new settings.")
    }

    func connect() async {
        guard connectionState == .disconnected || connectionState.isFailed else {
            logger.warning("Connection attempt ignored, already connected or connecting.")
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
            logger.info("OBD-II connected successfully.")
            startContinuousOBDUpdates()
        } catch {
            let errorMessage = error.localizedDescription
            connectionState = .failed(error)
            connectedPeripheralName = nil
            logger.error("OBD-II connection failed: \(errorMessage)")
        }
    }

    func disconnect() {
        obdService.stopConnection()
        cancellables.removeAll()
        pidStats.removeAll()
        connectedPeripheralName = nil
        connectionState = .disconnected
        logger.info("OBD-II disconnected.")
    }

    func resetAllStats() {
        pidStats = pidStats.mapValues { existing in
            var reset = existing
            reset.min = existing.latest.value
            reset.max = existing.latest.value
            reset.sampleCount = 1
            return reset
        }
        logger.info("All PID stats reset (min/max/sampleCount).")
    }

    func resetStats(for pid: OBDCommand) {
        guard var existing = pidStats[pid] else { return }
        existing.min = existing.latest.value
        existing.max = existing.latest.value
        existing.sampleCount = 1
        pidStats[pid] = existing
        logger.info("PID stats reset for \(String(describing: pid)).")
    }

    func stats(for pid: OBDCommand) -> PIDStats? {
        pidStats[pid]
    }

    private func startContinuousOBDUpdates() {
        cancellables.removeAll()

        // Re-establish mirror subscription after clearing cancellables
        obdService.$connectedPeripheral
            .map { $0?.name }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in
                self?.connectedPeripheralName = name
            }
            .store(in: &cancellables)

        // Build commands from the current enabled PIDs in the store.
        // If you want only gauges, use enabledGauges; otherwise include all enabled items.
        let enabledNow = Set(PIDStore.shared.pids.filter { $0.enabled }.map { $0.pid })

        startContinuousOBDUpdates(with: enabledNow)
    }

    private func startContinuousOBDUpdates(with enabledPIDs: Set<OBDCommand>) {
        cancellables.removeAll()
        
        var enabledNow = enabledPIDs
        if (querySupportedPids == true)
        {
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

        // Prune pidStats to only those still enabled (after support filtering)
        if !pidStats.isEmpty {
            let before = pidStats.count
            pidStats = pidStats.filter { enabledNow.contains($0.key) }
            let after = pidStats.count
            if before != after {
                logger.info("Pruned disabled/unsupported PIDs from pidStats: \(before - after) removed.")
            }
        }

        // Re-establish mirror subscription after clearing cancellables
        obdService.$connectedPeripheral
            .map { $0?.name }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in
                self?.connectedPeripheralName = name
            }
            .store(in: &cancellables)

        // FIX: enabledNow is already Set<OBDCommand>, do not wrap again
        let commands: [OBDCommand] = Array(enabledNow)

        guard !commands.isEmpty else {
            logger.info("No enabled PIDs to monitor.")
            return
        }

        logger.info("Starting continuous updates for \(commands.count) PIDs.")
        obdService
            .startContinuousUpdates(commands, unit: ConfigData.shared.units, interval: 1)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.logger.error("Continuous OBD updates failed: \(error.localizedDescription)")
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
            .store(in: &cancellables)
    }

    private func restartContinuousUpdates(with enabledPIDs: Set<OBDCommand>) {
        // Rebuild the stream with the exact enabled set that changed.
        cancellables.removeAll()

        // Re-establish mirror subscription after clearing cancellables
        obdService.$connectedPeripheral
            .map { $0?.name }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in
                self?.connectedPeripheralName = name
            }
            .store(in: &cancellables)

        startContinuousOBDUpdates(with: enabledPIDs)
    }
}

extension OBDConnectionManager.ConnectionState {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

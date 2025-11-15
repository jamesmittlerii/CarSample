/**
 
 * __Final Project__
 * Jim Mittler
 * 14 November 2025
 
 
Main class for managing our OBD2 comms through the SwiftOBD2 library
 
 _Italic text__
 __Bold text__
 ~~Strikethrough text~~
 
 */

import Foundation
import SwiftOBD2
import Combine
import CoreBluetooth

@MainActor
class OBDConnectionManager: ObservableObject {
    
    // keep track of our connection state
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

    // we want to ask OBD2 which pids are supported by the vehicle
    private let querySupportedPids = true
    
    // keep the list here
    private var supportedPids: [OBDCommand] = []
    
    // a static we can use for convenience
    static let shared = OBDConnectionManager()
    
    // our connection status
    @Published var connectionState: ConnectionState = .disconnected
    
    // current DTCs
    @Published var troubleCodes: [TroubleCodeMetadata]  = []
    
    // the FI/O2 sensor status
    @Published var fuelStatus: [StatusCodeMetadata?] = []
    
    // our MIL status
    @Published var MILStatus: Status?

    // publish the connected peripheral name (Bluetooth), or nil for Wi‑Fi/Demo/none
    @Published var connectedPeripheralName: String?

    // pid stats contains the data we've collected for a given PID
    struct PIDStats: Equatable {
        
        var pid: OBDCommand // the command
        var latest: MeasurementResult // our result
        var min: Double // smallest we've seen
        var max: Double // biggest
        var sampleCount: Int // number of samples we've seen

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

    // our collection of pids with stats
    @Published private(set) var pidStats: [OBDCommand: PIDStats] = [:]

    private var obdService: OBDService
    private var cancellables = Set<AnyCancellable>()           // general subscriptions (mirror, config, etc.)
    private var streamCancellables = Set<AnyCancellable>()     // continuous updates stream only

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

        // Observe demand-driven interest set from PIDInterestRegistry
        PIDInterestRegistry.shared.$interested
            .removeDuplicates()
            .sink { [weak self] interestedSet in
                guard let self else { return }
                // Prune pidStats for any PIDs that are no longer interested
                if !self.pidStats.isEmpty {
                    let before = self.pidStats.count
                    self.pidStats = self.pidStats.filter { interestedSet.contains($0.key) }
                    let after = self.pidStats.count
                    if before != after {
                        obdInfo("Pruned uninterested PIDs from pidStats: \(before - after) removed.", category: .service)
                    }
                }

                // Only (re)start if connected
                if self.connectionState == .connected {
                    self.restartContinuousUpdates(with: interestedSet)
                } else {
                    // If not connected, clear stream state so we start fresh later
                    self.streamCancellables.removeAll()
                    self.lastStreamingPIDs = []
                }
            }
            .store(in: &cancellables)

        // Observe units changes and restart stream with the same interest set
        ConfigData.shared.$unitsPublished
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let interestedSet = PIDInterestRegistry.shared.interested
                if self.connectionState == .connected {
                    obdInfo("Units changed to \(ConfigData.shared.units.rawValue); restarting continuous updates and resetting stats.", category: .service)
                    self.resetAllStats()
                    // clear this so we reset the units
                    lastStreamingPIDs = []
                    self.restartContinuousUpdates(with: interestedSet)
                } else {
                    self.resetAllStats()
                }
            }
            .store(in: &cancellables)
    }

    //  State mapping helpers

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
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] serviceState in
                self?.handleServiceConnectionState(serviceState)
            }
            .store(in: &cancellables)

        obdInfo("OBD Service re-initialized with new settings.", category: .service)
    }

    func connect() async {
        guard connectionState == .disconnected || connectionState.isFailed else {
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
            connectedPeripheralName = obdService.connectedPeripheral?.name
            obdInfo("OBD-II connected successfully.", category: .service)
            // Start with current interest set (may be empty)
            startContinuousOBDUpdates(with: PIDInterestRegistry.shared.interested)
        } catch {
            let errorMessage = error.localizedDescription
            connectionState = .failed(error)
            connectedPeripheralName = nil
            obdError("OBD-II connection failed: \(errorMessage)", category: .service)
        }
    }

    func disconnect() {
         obdService.stopConnection()
        cancellables.removeAll()
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

    private func startContinuousOBDUpdates(with interestedPIDs: Set<OBDCommand>) {
        startContinuousOBDUpdatesInternal(with: interestedPIDs)
    }

    private func startContinuousOBDUpdatesInternal(with interestedPIDs: Set<OBDCommand>) {
        // Filter by supported PIDs if requested
        var enabledNow = interestedPIDs
        if querySupportedPids {
            // Build the supported Mode 01 set
            let supportedMode1: Set<OBDCommand> = Set(
                supportedPids.compactMap { cmd in
                    if case let .mode1(m) = cmd { return .mode1(m) }
                    return nil
                }
            )

            // Keep all non-mode1; for mode1 keep only those present in supportedMode1
            let filtered: Set<OBDCommand> = Set(interestedPIDs.filter { cmd in
                switch cmd {
                case .mode1:
                    return supportedMode1.contains(cmd)
                default:
                    return true
                }
            })

            // Compute and log removed (unsupported) items among mode1
            let removed = interestedPIDs.subtracting(filtered)
            if !removed.isEmpty {
                obdDebug("removing unsupported mode1 pids: \(removed)")
            }

            enabledNow = filtered
        }

        // Skip if no commands
        guard !enabledNow.isEmpty else {
            obdInfo("No interested PIDs to monitor.", category: .service)
            if !lastStreamingPIDs.isEmpty {
                streamCancellables.removeAll()
                lastStreamingPIDs = []
            }
            return
        }

        // Skip if nothing changed
        if enabledNow == lastStreamingPIDs {
            obdInfo("Interested PIDs unchanged; not restarting continuous updates.", category: .service)
            return
        }

        // Prune pidStats to only those still in the interest set (after support filtering)
        if !pidStats.isEmpty {
            let before = pidStats.count
            pidStats = pidStats.filter { enabledNow.contains($0.key) }
            let after = pidStats.count
            if before != after {
                obdInfo("Pruned non-interested/unsupported PIDs from pidStats: \(before - after) removed.", category: .service)
            }
        }

        // Replace only the stream subscription
        streamCancellables.removeAll()

        let commands: [OBDCommand] = Array(enabledNow)
        lastStreamingPIDs = enabledNow

        obdInfo("Starting continuous updates for \(commands.count) PIDs (demand-driven).", category: .service)
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
                            if let measurement = decode.measurementResult {
                                let key: OBDCommand = command
                                var stats = self.pidStats[key] ?? PIDStats(pid: key, measurement: measurement)
                                stats.update(with: measurement)
                                self.pidStats[key] = stats
                            }
                        default:
                            continue
                        }
                    }
                }
            )
            .store(in: &streamCancellables)
    }

    private func restartContinuousUpdates(with interestedPIDs: Set<OBDCommand>) {
        // Force a rebuild by clearing and then starting fresh
        streamCancellables.removeAll()
        lastStreamingPIDs = []
        startContinuousOBDUpdatesInternal(with: interestedPIDs)
    }
}

extension OBDConnectionManager.ConnectionState {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}


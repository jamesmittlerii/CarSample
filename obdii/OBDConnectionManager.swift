import Foundation
import SwiftOBD2
import Combine
import os.log

@MainActor
class OBDConnectionManager: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String) // Using String for simple Equatable conformance

        static func == (lhs: OBDConnectionManager.ConnectionState, rhs: OBDConnectionManager.ConnectionState) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected):
                return true
            case (.connecting, .connecting):
                return true
            case (.connected, .connected):
                return true
            case let (.failed(lError), .failed(rError)):
                return lError == rError
            default:
                return false
            }
        }
    }

    static let shared = OBDConnectionManager()
    private let logger = Logger(subsystem: "com.rheosoft.obdii", category: "OBDConnection")

    @Published var connectionState: ConnectionState = .disconnected
    @Published var troubleCodes: [TroubleCodeMetadata]  = []

    // Track latest/min/max per PID
    struct PIDStats: Equatable {
        // Separate logger for the nested type
        private static let logger = Logger(subsystem: "com.rheosoft.obdii", category: "OBDConnection.PIDStats")

        var pid: OBDCommand.Mode1
        var latest: MeasurementResult
        var min: Double
        var max: Double
        var sampleCount: Int

        init(pid: OBDCommand.Mode1, measurement: MeasurementResult) {
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

    @Published private(set) var pidStats: [OBDCommand.Mode1: PIDStats] = [:]

    private var obdService: OBDService
    private var cancellables = Set<AnyCancellable>()
    private var pidStoreCancellable: AnyCancellable?

    private init() {
        //OBDLogger.shared.minimumLogLevel = .info
        self.obdService = OBDService(
            connectionType: .wifi,
            host: ConfigData.shared.wifiHost,
            port: UInt16(ConfigData.shared.wifiPort)
        )

        // Observe changes to enabled PIDs and restart streaming if connected
        pidStoreCancellable = PIDStore.shared.$pids
            .map { pids in pids.filter { $0.enabled }.map { $0.pid } }
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                if self.connectionState == .connected {
                    self.logger.info("Enabled PID set changed, restarting continuous updates.")
                    self.restartContinuousUpdates()
                }
            }
    }

    /// Call this if connection details in `ConfigData` have changed.
    func updateConnectionDetails() {
        if connectionState != .disconnected {
            disconnect()
        }
        self.obdService = OBDService(
            connectionType: .wifi,
            host: ConfigData.shared.wifiHost,
            port: UInt16(ConfigData.shared.wifiPort)
        )
        logger.info("OBD Service re-initialized with new settings.")
    }

    func connect() async {
        // Prevent multiple connection attempts
        guard connectionState == .disconnected || connectionState.isFailed else {
            logger.warning("Connection attempt ignored, already connected or connecting.")
            return
        }

        connectionState = .connecting

        do {
            _ = try await obdService.startConnection(preferedProtocol: .protocol6, querySupportedPIDs: false)
            let myTroubleCodes = try await obdService.scanForTroubleCodes()
            if (myTroubleCodes[SwiftOBD2.ECUID.engine] != nil) {
                troubleCodes = myTroubleCodes[SwiftOBD2.ECUID.engine]!
            }
            connectionState = .connected
            logger.info("OBD-II connected successfully.")
            startContinuousOBDUpdates()
        } catch {
            let errorMessage = error.localizedDescription
            connectionState = .failed(errorMessage)
            logger.error("OBD-II connection failed: \(errorMessage)")
        }
    }

    func disconnect() {
        obdService.stopConnection()
        cancellables.removeAll()
        pidStats.removeAll()
        connectionState = .disconnected
        logger.info("OBD-II disconnected.")
    }

    /// Reset min/max stats for all PIDs.
    func resetAllStats() {
        // Keep latest values but reset min/max/sampleCount to start from latest
        pidStats = pidStats.mapValues { existing in
            var reset = existing
            reset.min = existing.latest.value
            reset.max = existing.latest.value
            reset.sampleCount = 1
            return reset
        }
        logger.info("All PID stats reset (min/max/sampleCount).")
    }

    /// Reset min/max stats for a specific PID.
    func resetStats(for pid: OBDCommand.Mode1) {
        guard var existing = pidStats[pid] else { return }
        existing.min = existing.latest.value
        existing.max = existing.latest.value
        existing.sampleCount = 1
        pidStats[pid] = existing
        logger.info("PID stats reset for \(String(describing: pid)).")
    }

    /// Convenience accessor for a PID's stats.
    func stats(for pid: OBDCommand.Mode1) -> PIDStats? {
        pidStats[pid]
    }

    private func startContinuousOBDUpdates() {
        cancellables.removeAll()

        // Build commands from the user-configured enabled PIDs
        let commands: [OBDCommand] = PIDStore.shared.enabledPIDs
            .map { .mode1($0.pid) }

        guard !commands.isEmpty else {
            logger.info("No enabled PIDs to monitor.")
            return
        }

        obdService
            .startContinuousUpdates(commands,interval: 1)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.logger.error("Continuous OBD updates failed: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] measurements in
                    guard let self else { return }
                    for (command, result) in measurements {
                        if case let .mode1(pid) = command {
                            self.pidStats[pid, default: PIDStats(pid: pid, measurement: result)]
                                .update(with: result)
                        }
                    }
                }
            )
            .store(in: &cancellables)
    }

    private func restartContinuousUpdates() {
        // Option A: Do not stop the underlying connection; just rebuild the stream.
        cancellables.removeAll()
        startContinuousOBDUpdates()
    }
}

extension OBDConnectionManager.ConnectionState {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

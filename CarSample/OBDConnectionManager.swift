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
    private let logger = Logger(subsystem: "com.CarSample", category: "OBDConnection")

    @Published var connectionState: ConnectionState = .disconnected
    @Published private(set) var latestMeasurements: [OBDCommand.Mode1: MeasurementResult] = [:]

    // Track running min/max per PID
    struct PIDStats: Equatable {
        var min: Double
        var max: Double
        var sampleCount: Int

        init(value: Double) {
            self.min = value
            self.max = value
            self.sampleCount = 1
        }

        mutating func update(with value: Double) {
            if value < min { min = value }
            if value > max { max = value }
            sampleCount &+= 1
        }
    }
    @Published private(set) var pidStats: [OBDCommand.Mode1: PIDStats] = [:]

    private var obdService: OBDService
    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.obdService = OBDService(
            connectionType: .wifi,
            host: ConfigData.shared.wifiHost,
            port: UInt16(ConfigData.shared.wifiPort)
        )
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
            _ = try await obdService.startConnection()
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
        latestMeasurements.removeAll()
        pidStats.removeAll()
        connectionState = .disconnected
        logger.info("OBD-II disconnected.")
    }

    /// Reset min/max stats for all PIDs.
    func resetAllStats() {
        pidStats.removeAll()
        logger.info("All PID stats reset.")
    }

    /// Reset min/max stats for a specific PID.
    func resetStats(for pid: OBDCommand.Mode1) {
        pidStats[pid] = nil
        logger.info("PID stats reset for \(String(describing: pid)).")
    }

    /// Convenience accessor for a PID's stats.
    func stats(for pid: OBDCommand.Mode1) -> PIDStats? {
        pidStats[pid]
    }

    private func startContinuousOBDUpdates() {
        cancellables.removeAll()

        for pid in OBDPIDLibrary.standard {
            if pid.enabled == false {
                continue
            }
            let command = OBDCommand.mode1(pid.pid)
            obdService
                .startContinuousUpdates([command])
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { [weak self] completion in
                        if case .failure(let error) = completion {
                            self?.logger.error("Continuous OBD updates failed: \(error.localizedDescription)")
                            // Optionally update state to failed
                          //  self?.connectionState = .failed("Streaming failed: \(error.localizedDescription)")
                        }
                    },
                    receiveValue: { [weak self] measurements in
                        guard let self else { return }
                        for (cmd, result) in measurements {
                            // Update latest measurement
                            self.latestMeasurements[pid.pid] = result

                            // Update min/max stats
                            let value = result.value
                            if var existing = self.pidStats[pid.pid] {
                                existing.update(with: value)
                                self.pidStats[pid.pid] = existing
                            } else {
                                self.pidStats[pid.pid] = PIDStats(value: value)
                            }
                        }
                    }
                )
                .store(in: &cancellables)
        }
    }
}

extension OBDConnectionManager.ConnectionState {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

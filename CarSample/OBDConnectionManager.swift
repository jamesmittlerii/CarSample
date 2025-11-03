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
    @Published private(set) var latestMeasurements: [OBDCommand: MeasurementResult] = [:]

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
        connectionState = .disconnected
        logger.info("OBD-II disconnected.")
    }

    private func startContinuousOBDUpdates() {
        cancellables.removeAll()

        for pid in OBDPIDLibrary.standard {
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
                            self.latestMeasurements[cmd] = result
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

//
//  SettingsView.swift
//  CarSample
//
//  Created by cisstudent on 11/3/25.
//

import SwiftUI
import SwiftOBD2
#if canImport(UIKit)
import UIKit
#endif

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    // Share sheet state (iOS only)
    #if canImport(UIKit)
    @State private var isPresentingShare = false
    @State private var shareItems: [Any] = []
    @State private var isGeneratingLogs = false
    @State private var shareError: String?
    #endif

    // Runtime detection: iOS app running on macOS (Designed for iPad) or Mac Catalyst
    private var runningOnMac: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        if #available(iOS 14.0, *) {
            return ProcessInfo.processInfo.isiOSAppOnMac
        } else {
            return false
        }
        #endif
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    NavigationLink("Gauges") {
                        PIDToggleListView()
                    }
                }

                Section(header: Text("Connection")) {
                    HStack {
                        Text("Status")
                        Spacer()
                        statusTextView()
                    }

                    Picker("Type", selection: $viewModel.connectionType) {
                        ForEach(ConnectionType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    Toggle("Automatically Connect", isOn: $viewModel.autoConnectToOBD)

                    connectDisconnectButton()
                }

                if viewModel.connectionType == .wifi {
                    Section(header: Text("Connection Details")) {
                        HStack {
                            Text("Host")
                            Spacer()
                            TextField("e.g., 192.168.0.10", text: $viewModel.wifiHost)
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .multilineTextAlignment(.trailing)
                        }

                        HStack {
                            Text("Port")
                            Spacer()
                            TextField("e.g., 35000", value: $viewModel.wifiPort, formatter: viewModel.numberFormatter)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                Section(header: Text("Diagnostics")) {
                    #if canImport(UIKit)
                    Button {
                        // If running on macOS (Designed for iPad or Catalyst), do nothing.
                        if runningOnMac { return }
                        Task { await shareLogs_iOS() }
                    } label: {
                        if isGeneratingLogs {
                            HStack {
                                ProgressView()
                                Text("Preparing Logs…")
                            }
                        } else {
                            Text("Share Logs")
                        }
                    }
                    .disabled(isGeneratingLogs || runningOnMac)
                    .alert("Could not prepare logs", isPresented: .constant(shareError != nil), actions: {
                        Button("OK") { shareError = nil }
                    }, message: {
                        Text(shareError ?? "")
                    })
                    #else
                    Button {
                        // Non-UIKit platforms: unavailable
                    } label: {
                        Text("Share Logs")
                    }
                    .disabled(true)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
                    #endif
                }
            }
            .navigationTitle("Settings")
            #if canImport(UIKit)
            .sheet(isPresented: $isPresentingShare, onDismiss: {
                shareItems = []
            }, content: {
                ShareSheet(activityItems: shareItems)
            })
            #endif
        }
    }

    @ViewBuilder
    private func statusTextView() -> some View {
        switch viewModel.connectionState {
        case .disconnected:
            Text("Disconnected")
                .foregroundColor(.gray)
        case .connecting:
            Text("Connecting...")
                .foregroundColor(.orange)
        case .connected:
            Text("Connected")
                .foregroundColor(.green)
        case .failed(_):
            Text("Failed")
                .foregroundColor(.red)
        }
    }

    @ViewBuilder
    private func connectDisconnectButton() -> some View {
        HStack {
            Spacer()
            Button(action: viewModel.handleConnectionButtonTap) {
                switch viewModel.connectionState {
                case .disconnected, .failed:
                    Text("Connect")
                case .connecting:
                    HStack {
                        Text("Connecting...")
                        ProgressView().padding(.leading, 2)
                    }
                case .connected:
                    Text("Disconnect")
                }
            }
            .disabled(viewModel.isConnectButtonDisabled)
            Spacer()
        }
    }

    // MARK: - Share Logs (UIKit)

    #if canImport(UIKit)
    private func shareLogs_iOS() async {
        isGeneratingLogs = true
        defer { isGeneratingLogs = false }

        do {
            let data = try await collectLogs(since: -300) // last 5 minutes
            let tempURL = try writeToTemporaryFile(data: data, suggestedName: "SwiftOBD2-logs.json")
            shareItems = [tempURL]
            isPresentingShare = true
        } catch {
            shareError = error.localizedDescription
        }
    }
    #endif

    // MARK: - Common helper

    private func writeToTemporaryFile(data: Data, suggestedName: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(suggestedName)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
}

#if canImport(UIKit)
// MARK: - UIKit Share Sheet Wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
#endif

#Preview {
    SettingsView()
}

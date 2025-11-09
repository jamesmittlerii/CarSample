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
#if canImport(AppKit)
import AppKit
#endif

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    // Share sheet state
    #if canImport(UIKit)
    @State private var isPresentingShare = false
    @State private var shareItems: [Any] = []
    @State private var isGeneratingLogs = false
    @State private var shareError: String?
    #endif

    #if canImport(AppKit)
    @State private var isGeneratingLogsMac = false
    @State private var shareErrorMac: String?
    // Anchor for NSSharingServicePicker
    @State private var macShareAnchorFrame: CGRect = .zero
    #endif

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
                    .disabled(isGeneratingLogs)
                    .alert("Could not prepare logs", isPresented: .constant(shareError != nil), actions: {
                        Button("OK") { shareError = nil }
                    }, message: {
                        Text(shareError ?? "")
                    })
                    #else
                    HStack {
                        Text("Share Logs")
                        Spacer()
                        Text("Unavailable on this platform")
                            .foregroundColor(.secondary)
                    }
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

    // MARK: - Share Logs (AppKit)

    #if canImport(AppKit)
    private func shareLogs_mac(anchorView: NSView) async {
        isGeneratingLogsMac = true
        defer { isGeneratingLogsMac = false }

        do {
            let data = try await collectLogs(since: -300)
            let tempURL = try writeToTemporaryFile(data: data, suggestedName: "SwiftOBD2-logs.json")
            let picker = NSSharingServicePicker(items: [tempURL])
            picker.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        } catch {
            shareErrorMac = error.localizedDescription
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

#if canImport(AppKit)
// MARK: - macOS Share Logs Button

private struct ShareLogsMacButton: NSViewRepresentable {
    @Binding var isGenerating: Bool
    @Binding var errorMessage: String?
    let action: (NSView) -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "Share Logs", target: context.coordinator, action: #selector(Coordinator.tapped))
        button.bezelStyle = .rounded
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        nsView.isEnabled = !isGenerating
        nsView.title = isGenerating ? "Preparing Logs…" : "Share Logs"
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        let parent: ShareLogsMacButton
        init(_ parent: ShareLogsMacButton) { self.parent = parent }

        @objc func tapped(_ sender: NSButton) {
            parent.action(sender)
        }
    }
}
#endif

#Preview {
    SettingsView()
}

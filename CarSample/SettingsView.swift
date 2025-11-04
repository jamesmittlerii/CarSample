//
//  SettingsView.swift
//  CarSample
//
//  Created by cisstudent on 11/3/25.
//


import SwiftUI

struct SettingsView: View {
    @ObservedObject var configData = ConfigData.shared
    @ObservedObject var connectionManager = OBDConnectionManager.shared

    // Formatter to ensure the port is entered as a number
    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        return formatter
    }()

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Connection")) {
                    HStack {
                        Text("Status")
                        Spacer()
                        statusTextView()
                    }
                    
                    Toggle("Automatically Connect", isOn: $configData.autoConnectToOBD)
                    
                    connectDisconnectButton()
                }

                Section(header: Text("Wi-Fi Connection Details")) {
                    HStack {
                        Text("Host")
                        Spacer()
                        TextField("e.g., 192.168.0.10", text: $configData.wifiHost)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("e.g., 35000", value: $configData.wifiPort, formatter: numberFormatter)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle("Settings")
            .onChange(of: configData.wifiHost) { _, _ in connectionManager.updateConnectionDetails() }
            .onChange(of: configData.wifiPort) { _, _ in connectionManager.updateConnectionDetails() }
        }
    }
    
    @ViewBuilder
    private func statusTextView() -> some View {
        switch connectionManager.connectionState {
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
                // In a real app, you might show the 'error' string in an alert here
        }
    }

    @ViewBuilder
    private func connectDisconnectButton() -> some View {
        HStack {
            Spacer()
            Button(action: handleConnectionButtonTap) {
                switch connectionManager.connectionState {
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
            .disabled(connectionManager.connectionState == .connecting)
            Spacer()
        }
    }
    
    private func handleConnectionButtonTap() {
        switch connectionManager.connectionState {
        case .connected:
            connectionManager.disconnect()
        case .disconnected, .failed:
            // Ensure connection details are up-to-date before connecting
            connectionManager.updateConnectionDetails()
            Task {
                await connectionManager.connect()
            }
        case .connecting:
            // Button is disabled, so this case shouldn't be reached
            break
        }
    }
}

#Preview {
    SettingsView()
}

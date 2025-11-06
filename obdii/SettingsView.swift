//
//  SettingsView.swift
//  CarSample
//
//  Created by cisstudent on 11/3/25.
//


import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

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
                    
                    Toggle("Automatically Connect", isOn: $viewModel.autoConnectToOBD)
                    
                    connectDisconnectButton()
                }

                Section(header: Text("Wi-Fi Connection Details")) {
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
            .navigationTitle("Settings")
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
}

#Preview {
    SettingsView()
}

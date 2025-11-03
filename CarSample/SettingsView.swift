//
//  SettingsView.swift
//  CarSample
//
//  Created by cisstudent on 11/3/25.
//


import SwiftUI

struct SettingsView: View {
    @ObservedObject var configData = ConfigData.shared

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
                    Toggle("Automatically Connect", isOn: $configData.autoConnectToOBD)
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
        }
    }
}

#Preview {
    SettingsView()
}

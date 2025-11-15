/**
 
 * __Final Project__
 * Jim Mittler
 * 14 November 2025
 
 
Swift UI view for the FI/O2 sensor detail
 
 _Italic text__
 __Bold text__
 ~~Strikethrough text~~
 
 */

import SwiftUI
import Combine
import SwiftOBD2

struct FuelStatusView: View {
    @StateObject private var viewModel = FuelStatusViewModel()
    // Token for demand-driven polling
    @State private var interestToken: UUID = PIDInterestRegistry.shared.makeToken()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let b1 = viewModel.bank1 {
                        HStack(spacing: 12) {
                            Image(systemName: "fuelpump.fill")
                                .foregroundStyle(.blue)
                                .imageScale(.large)
                            Text("Bank 1")
                            Spacer()
                            Text(b1.description)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                        .accessibilityLabel("Bank 1, \(b1.description)")
                    }

                    if let b2 = viewModel.bank2 {
                        HStack(spacing: 12) {
                            Image(systemName: "fuelpump.fill")
                                .foregroundStyle(.blue)
                                .imageScale(.large)
                            Text("Bank 2")
                            Spacer()
                            Text(b2.description)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                        .accessibilityLabel("Bank 2, \(b2.description)")
                    }

                    if !viewModel.hasAnyStatus {
                        Label("No Fuel System Status Codes", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("No Fuel System Status Codes")
                    }
                }
            }
            .navigationTitle("Fuel Control Status")
        }
        .onAppear {
            PIDInterestRegistry.shared.replace(pids: [.mode1(.fuelStatus)], for: interestToken)
        }
        .onDisappear {
            PIDInterestRegistry.shared.clear(token: interestToken)
        }
    }
}

#Preview {
    FuelStatusView()
}


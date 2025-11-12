import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }

            GaugesView()
                .tabItem {
                    Image(systemName: "gauge")
                    Text("Gauges")
                }

            FuelStatusView()
                .tabItem {
                    Image(systemName: "fuelpump.fill")
                    Text("Fuel")
                }

            MILStatusView()
                .tabItem {
                    Image(systemName: "engine.combustion.fill")
                    Text("MIL")
                }

            DiagnosticsView()
                .tabItem {
                    Image(systemName: "wrench.and.screwdriver")
                    Text("DTCs")
                }
        }
    }
}

#Preview {
    RootTabView()
}

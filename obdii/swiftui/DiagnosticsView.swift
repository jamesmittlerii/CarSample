import SwiftUI
import SwiftOBD2

struct DiagnosticsView: View {
    @StateObject private var viewModel = DiagnosticsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isEmpty {
                    List {
                        Text("No Diagnostic Trouble Codes")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        ForEach(viewModel.sections, id: \.title) { section in
                            Section(header: Text(section.title)) {
                                ForEach(section.items, id: \.code) { code in
                                    NavigationLink {
                                        DTCDetailView(code: code)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: imageName(for: code.severity))
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("\(code.code) • \(code.title)")
                                                    .lineLimit(1)
                                                Text(code.severity.rawValue)
                                                    .font(.footnote)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Diagnostic Codes")
        }
    }
}

#Preview {
    DiagnosticsView()
}

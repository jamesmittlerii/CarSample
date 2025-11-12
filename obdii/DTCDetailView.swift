import SwiftUI
import SwiftOBD2

struct DTCDetailView: View {
    let code: TroubleCodeMetadata

    var body: some View {
        List {
            Section(header: Text("Overview")) {
                LabeledContent("Code", value: code.code)
                LabeledContent("Title", value: code.title)
                LabeledContent("Severity", value: code.severity.rawValue)
            }

            Section(header: Text("Description")) {
                Text(code.description)
            }

            if !code.causes.isEmpty {
                Section(header: Text("Potential Causes")) {
                    ForEach(code.causes, id: \.self) { cause in
                        Text("• \(cause)")
                    }
                }
            }

            if !code.remedies.isEmpty {
                Section(header: Text("Possible Remedies")) {
                    ForEach(code.remedies, id: \.self) { remedy in
                        Text("• \(remedy)")
                    }
                }
            }
        }
        .navigationTitle(code.code)
    }
}

#Preview {
    // Use a real entry from the public dictionary if available
    let sample = troubleCodeDictionary["P0300"] ?? troubleCodeDictionary.values.first!
    NavigationStack { DTCDetailView(code: sample) }
}

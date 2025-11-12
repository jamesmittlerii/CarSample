import CarPlay
import UIKit
import SwiftOBD2
import Combine

@MainActor
class CarPlayDiagnosticsController {
    private weak var interfaceController: CPInterfaceController?
    private var currentTemplate: CPListTemplate?
    private let connectionManager: OBDConnectionManager
    private var cancellables = Set<AnyCancellable>()
    
    init(connectionManager: OBDConnectionManager) {
        self.connectionManager = connectionManager
        
       
    }

    func setInterfaceController(_ interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        
        // Observe connection state changes to keep the UI in sync
        OBDConnectionManager.shared.$troubleCodes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSection()
            }
            .store(in: &cancellables)
    }
    
    private func makeItem(_ text: String, detailText: String?) -> CPListItem {
        let item = CPListItem(text: text, detailText: detailText)
        item.handler = { _, completion in completion() }
        return item
    }
     
    private func buildSections() -> [CPListSection] {
        let codes = connectionManager.troubleCodes

        // No DTCs → single info row
        if codes.isEmpty {
            let item = makeItem("No Diagnostic Trouble Codes", detailText: nil)
            let section = CPListSection(items: [item])
           return [section]
        }

        // Group codes by severity
        let grouped = Dictionary(grouping: codes, by: { $0.severity })

        // Ordered severity buckets (Critical → Low)
        let order: [CodeSeverity] = [.critical, .high, .moderate, .low]

        let sections: [CPListSection] = order.compactMap { severity -> CPListSection? in
            guard let list = grouped[severity] else { return nil }

            let items: [CPListItem] = list.map { code in
                let item = CPListItem(
                    text: "\(code.code) • \(code.title)",
                    detailText: code.severity.rawValue
                )
                item.setImage(
                    tintedSymbol(
                        named: imageName(for: code.severity),
                        severity: code.severity
                    )
                )
                item.handler = { [weak self] _, completion in
                    self?.presentOBDDetail(for: code)
                    completion()
                }
                return item
            }

            return CPListSection(items: items,
                                 header: severitySectionTitle(severity),
                                 sectionIndexTitle: nil)
        }
        return sections;
    }

    private func refreshSection() {
        guard let template = currentTemplate else { return }
        let sections = buildSections()
        template.updateSections(sections)
    }

    /// Creates the root template for the Settings tab.
    func makeRootTemplate() -> CPListTemplate {
        let sections = buildSections()
        let template = CPListTemplate(title: "DTCs", sections: sections)
        template.tabTitle = "DTCs"
        template.tabImage = symbolImage(named: "wrench.and.screwdriver")
        self.currentTemplate = template
        return template
    }
    
    private func presentOBDDetail(for code: TroubleCodeMetadata) {
        var items: [CPInformationItem] = [
            CPInformationItem(title: "Code", detail: code.code),
            CPInformationItem(title: "Title", detail: code.title),
            CPInformationItem(title: "Severity", detail: code.severity.rawValue),
            CPInformationItem(title: "Description", detail: code.description)
        ]

        if !code.causes.isEmpty {
            let causesText = code.causes.map { "• \($0)" }.joined(separator: "\n")
            items.append(CPInformationItem(title: "Potential Causes", detail: causesText))
        }

        if !code.remedies.isEmpty {
            let remediesText = code.remedies.map { "• \($0)" }.joined(separator: "\n")
            items.append(CPInformationItem(title: "Possible Remedies", detail: remediesText))
        }

        let template = CPInformationTemplate(
            title: "DTC \(code.code)",
            layout: .twoColumn,
            items: items,
            actions: []
        )
        interfaceController?.pushTemplate(template, animated: false, completion: nil)
    }

    // MARK: - Helpers

   
}

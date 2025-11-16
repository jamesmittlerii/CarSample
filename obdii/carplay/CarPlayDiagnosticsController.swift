/**
 
 * __Final Project__
 * Jim Mittler
 * 14 November 2025
 
 
CarPlay template for DTCs
 
 _Italic text__
 __Bold text__
 ~~Strikethrough text~~
 
 */

import CarPlay
import UIKit
import SwiftOBD2
import Combine

@MainActor
class CarPlayDiagnosticsController: CarPlayBaseTemplateController {
    private let viewModel: DiagnosticsViewModel
    private var cancellables = Set<AnyCancellable>()
    
    init(connectionManager: OBDConnectionManager) {
        // Use the shared diagnostics ViewModel logic
        self.viewModel = DiagnosticsViewModel(connectionManager: connectionManager)
    }

    override func setInterfaceController(_ interfaceController: CPInterfaceController) {
        super.setInterfaceController(interfaceController)
        
        subscribeAndRefresh(viewModel.$sections)
        
    }
    
    // Ensure demand-driven streaming includes fuel status while this tab is visible
    override func registerVisiblePIDs() {
        PIDInterestRegistry.shared.replace(pids: [.mode3(.GET_DTC)], for: controllerToken)
    }
    
    private func makeItem(_ text: String, detailText: String?) -> CPListItem {
        let item = CPListItem(text: text, detailText: detailText)
        item.handler = { _, completion in completion() }
        return item
    }
     
    private func buildSections() -> [CPListSection] {
        // No DTCs → single info row
        if viewModel.sections.isEmpty {
            let item = makeItem("No Diagnostic Trouble Codes", detailText: nil)
            let section = CPListSection(items: [item])
            return [section]
        }

        // Build sections from the ViewModel’s grouped/ordered data
        let sections: [CPListSection] = viewModel.sections.map { section in
            let items: [CPListItem] = section.items.map { code in
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
                                 header: section.title,
                                 sectionIndexTitle: nil)
        }
        return sections
    }

    private func refreshSection() {
        guard let template = currentTemplate as? CPListTemplate else { return }
        let sections = buildSections()
        template.updateSections(sections)
    }

    /// Creates the root template for the Settings tab.
    override func makeRootTemplate() -> CPListTemplate {
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

    // Hook for base class visibility refresh
    override func performRefresh() {
        refreshSection()
    }

    //  Helpers
}


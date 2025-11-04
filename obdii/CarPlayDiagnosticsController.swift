import CarPlay
import UIKit

@MainActor
class CarPlayDiagnosticsController {
    private weak var interfaceController: CPInterfaceController?

    func setInterfaceController(_ interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
    }

    /// Creates the root template for the Diagnostics tab.
    func makeRootTemplate() -> CPListTemplate {
        let items: [CPListItem] = [
            {
                let count = exampleOBDCodes.count
                let statusText = count == 0 ? "No DTCs" : "\(count) Code\(count == 1 ? "" : "s")"
                let item = CPListItem(text: "OBD-II Status", detailText: statusText)
                item.handler = { [weak self] _, completion in
                    guard let self else { completion(); return }
                    let obdTemplate = self.makeOBDListTemplate(codes: exampleOBDCodes)
                    self.interfaceController?.pushTemplate(obdTemplate, animated: true, completion: nil)
                    completion()
                }
                return item
            }()
        ]
        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "Diagnostics", sections: [section])
        template.tabTitle = "Diagnostics"
        template.tabImage = symbolImage(named: "wrench.and.screwdriver")
        return template
    }

    private func makeOBDListTemplate(codes: [OBDCode]) -> CPListTemplate {
        func imageName(for severity: OBDCode.Severity) -> String {
            switch severity {
            case .low: "exclamationmark.circle"
            case .moderate: "exclamationmark.triangle"
            case .high: "bolt.trianglebadge.exclamationmark"
            case .critical: "xmark.octagon"
            }
        }

        let items: [CPListItem] = codes.map { code in
            let item = CPListItem(text: "\(code.code) • \(code.title)", detailText: code.severity.rawValue)
            item.setImage(symbolImage(named: imageName(for: code.severity)))
            item.handler = { [weak self] _, completion in
                self?.presentOBDDetail(for: code)
                completion()
            }
            return item
        }

        let section = CPListSection(items: items)
        return CPListTemplate(title: "OBD-II Diagnostic Codes", sections: [section])
    }

    private func presentOBDDetail(for code: OBDCode) {
        let items: [CPInformationItem] = [
            CPInformationItem(title: "Code", detail: code.code),
            CPInformationItem(title: "Title", detail: code.title),
            CPInformationItem(title: "Severity", detail: code.severity.rawValue),
            CPInformationItem(title: "Description", detail: code.description)
        ]
        let template = CPInformationTemplate(title: "DTC \(code.code)", layout: .twoColumn, items: items, actions: [])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }
}

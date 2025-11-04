import CarPlay
import UIKit

@MainActor
class CarPlaySettingsController {
    private weak var interfaceController: CPInterfaceController?

    func setInterfaceController(_ interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
    }

    /// Creates the root template for the Settings tab.
    func makeRootTemplate() -> CPListTemplate {
        let items: [CPListItem] = [
            CPListItem(text: "Units", detailText: "Metric"),
            CPListItem(text: "Theme", detailText: "Automatic"),
            CPListItem(text: "About", detailText: "Version 1.0")
        ]
        // Add empty handlers for now
        items.forEach { $0.handler = { _, completion in completion() } }
        
        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "Settings", sections: [section])
        template.tabTitle = "Settings"
        template.tabImage = symbolImage(named: "gear")
        return template
    }
}

import UIKit
import SwiftOBD2
import CarPlay
import os.log
import Combine
import SwiftUI

protocol CarPlayTabControlling: AnyObject {
    /// Return the root CPTemplate for this tab.
    func makeRootTemplate() -> CPTemplate

    /// Called when the CarPlaySceneDelegate supplies the active interface controller.
    func setInterfaceController(_ interfaceController: CPInterfaceController)

    /// Called when the tab coordinator publishes tab selections.
    func setTabSelectionPublisher(_ publisher: AnyPublisher<Int, Never>, tabIndex: Int)
}

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    var interfaceController: CPInterfaceController?
    private let logger = Logger()
    private let connectionManager = OBDConnectionManager.shared
    private let tabCoordinator = CarPlayTabCoordinator()

    // Tab Controllers
    private lazy var controllers: [any CarPlayTabControlling] = [
        CarPlayGaugesController(connectionManager: connectionManager),
        CarPlayFuelStatusController(connectionManager: connectionManager),
        CarPlayMILStatusController(connectionManager: connectionManager),
        CarPlayDiagnosticsController(connectionManager: connectionManager),
        CarPlaySettingsController()
    ]

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {

        self.interfaceController = interfaceController

        // 1) Provide interface controller to all tab controllers
        controllers.forEach { $0.setInterfaceController(interfaceController) }

        // 2) Build templates from controllers
        let templates = controllers.map { $0.makeRootTemplate() }

        // 3) Create tab bar
        let tabBar = CPTabBarTemplate(templates: templates)
        tabBar.delegate = tabCoordinator

        // 4) Inject selection publisher + index for each controller
        for (index, controller) in controllers.enumerated() {
            controller.setTabSelectionPublisher(
                tabCoordinator.selectedIndexPublisher,
                tabIndex: index
            )
        }

        // 5) Set root template
        interfaceController.setRootTemplate(tabBar, animated: true, completion: nil)

        // 6) Restore previous tab selection (async required due to CarPlay timing)
        let savedIndex = UserDefaults.standard.integer(forKey: "selectedCarPlayTab")

        DispatchQueue.main.async { [weak tabBar] in
            guard let tabBar, (0..<tabBar.templates.count).contains(savedIndex) else { return }
            tabBar.selectTemplate(at: savedIndex)
        }

        // 7) Auto-connect to OBD if enabled
        if ConfigData.shared.autoConnectToOBD {
            Task { await connectionManager.connect() }
        }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
            didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
    }
}

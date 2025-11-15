/**
 
 * __Final Project__
 * Jim Mittler
 * 14 November 2025
 
 
CarPlay main scene
 
 _Italic text__
 __Bold text__
 ~~Strikethrough text~~
 
 */

import UIKit
import SwiftOBD2
// CarPlay App Lifecycle

import CarPlay
import os.log
import Combine
import SwiftUI

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?
    let logger = Logger()
    
    // Models and Services
    private let connectionManager = OBDConnectionManager.shared
    
    let tabCoordinator = CarPlayTabCoordinator()
    
    // Tab Controllers
    private lazy var gaugesController = CarPlayGaugesController(connectionManager: self.connectionManager)
    private lazy var diagnosticsController = CarPlayDiagnosticsController(connectionManager: self.connectionManager)
    private lazy var settingsController = CarPlaySettingsController()
    private lazy var fuelStatusController = CarPlayFuelStatusController(connectionManager: self.connectionManager)
    private lazy var milStatusController = CarPlayMILStatusController(connectionManager: self.connectionManager)
    
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
            didConnect interfaceController: CPInterfaceController) {

        self.interfaceController = interfaceController
        
        // Provide the interface controller to each tab controller
        gaugesController.setInterfaceController(interfaceController)
        diagnosticsController.setInterfaceController(interfaceController)
        settingsController.setInterfaceController(interfaceController)
        fuelStatusController.setInterfaceController(interfaceController)
        milStatusController.setInterfaceController(interfaceController)

        // Build the tabs by requesting the root template from each controller
        let gaugesTemplate = gaugesController.makeRootTemplate()
        let fuelStatusTemplate = fuelStatusController.makeRootTemplate()
        let milTemplate = milStatusController.makeRootTemplate()
        let diagnosticsTemplate = diagnosticsController.makeRootTemplate()
        let settingsTemplate = settingsController.makeRootTemplate()

        // Create the tab bar in the same order you will wire tab indices
        let tabBar = CPTabBarTemplate(templates: [
            gaugesTemplate,           // index 0
            fuelStatusTemplate,       // index 1
            milTemplate,              // index 2
            diagnosticsTemplate,      // index 3
            settingsTemplate          // index 4
        ])

        // Coordinator publishes selection and persists last tab
        tabBar.delegate = tabCoordinator

        // Inject selection publisher and tab indices (order must match the templates array above)
        gaugesController.setTabSelectionPublisher(tabCoordinator.selectedIndexPublisher, tabIndex: 0)
        fuelStatusController.setTabSelectionPublisher(tabCoordinator.selectedIndexPublisher, tabIndex: 1)
        milStatusController.setTabSelectionPublisher(tabCoordinator.selectedIndexPublisher, tabIndex: 2)
        diagnosticsController.setTabSelectionPublisher(tabCoordinator.selectedIndexPublisher, tabIndex: 3)
        settingsController.setTabSelectionPublisher(tabCoordinator.selectedIndexPublisher, tabIndex: 4)

        // Set the tab bar as root first so selection will take effect
        interfaceController.setRootTemplate(tabBar,
                                            animated: true,
                                            completion: nil)

        // Now restore previously selected tab by selecting its index
        let initialIndex = UserDefaults.standard.integer(forKey: "selectedCarPlayTab")
        
        // we have to run this though async for some reason
        DispatchQueue.main.async {
            if (0..<tabBar.templates.count).contains(initialIndex) {
                tabBar.selectTemplate(at: initialIndex)
                // the picker always selects gauges for some reason
                
            }
        }
        
        // Start OBD-II connection automatically if enabled
        if ConfigData.shared.autoConnectToOBD {
            Task {
                await connectionManager.connect()
            }
        }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
    }
}


//
//  CarPlaySceneDelegate.swift
//  CarPlay
//
//  Created by Alexander v. Below on 24.06.20.
//

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
    private var measurementCancellable: AnyCancellable?
    private var pidEnabledCancellable: AnyCancellable?   // NEW: observe enabled PID changes
    
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

        // Build the three tabs by requesting the root template from each controller
        let gaugesTemplate = gaugesController.makeRootTemplate()
        let milTemplate = milStatusController.makeRootTemplate()
        let diagnosticsTemplate = diagnosticsController.makeRootTemplate()
        let settingsTemplate = settingsController.makeRootTemplate()
        let fuelStatusTemplate = fuelStatusController.makeRootTemplate( )

        let tabBar = CPTabBarTemplate(templates: [gaugesTemplate, fuelStatusTemplate, milTemplate, diagnosticsTemplate, settingsTemplate])
        
        interfaceController.setRootTemplate(tabBar,
                                            animated: true,
                                            completion: nil)
        
        // Start OBD-II connection automatically if enabled
        if ConfigData.shared.autoConnectToOBD {
            Task {
                await connectionManager.connect()
            }
        }
        
       
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
        measurementCancellable?.cancel()
        pidEnabledCancellable?.cancel() // NEW: cancel the PID enabled subscription
    }
}

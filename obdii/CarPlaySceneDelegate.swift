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
    
    // Tab Controllers
    private lazy var gaugesController = CarPlayGaugesController(connectionManager: self.connectionManager)
    private lazy var diagnosticsController = CarPlayDiagnosticsController()
    private lazy var settingsController = CarPlaySettingsController()
    
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
            didConnect interfaceController: CPInterfaceController) {

        self.interfaceController = interfaceController
        
        // Provide the interface controller to each tab controller
        gaugesController.setInterfaceController(interfaceController)
        diagnosticsController.setInterfaceController(interfaceController)
        settingsController.setInterfaceController(interfaceController)

        // Build the three tabs by requesting the root template from each controller
        let gaugesTemplate = gaugesController.makeRootTemplate()
        let diagnosticsTemplate = diagnosticsController.makeRootTemplate()
        let settingsTemplate = settingsController.makeRootTemplate()

        let tabBar = CPTabBarTemplate(templates: [gaugesTemplate, diagnosticsTemplate, settingsTemplate])
        
        interfaceController.setRootTemplate(tabBar,
                                            animated: true,
                                            completion: nil)
        
        // Start OBD-II connection automatically if enabled
        if ConfigData.shared.autoConnectToOBD {
            Task {
                await connectionManager.connect()
            }
        }
        
        // Subscribe to PID stats updates and notify the gauges controller to refresh
        measurementCancellable = connectionManager.$pidStats
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.gaugesController.refresh()
            }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
        measurementCancellable?.cancel()
    }
}

//
//  ViewController.swift
//  CarSample
//
//  Created by Alexander v. Below on 24.06.20.
//

import UIKit
import SwiftUI

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Create the SwiftUI settings view
        let settingsView = SettingsView()
        
        // Use a UIHostingController to embed the SwiftUI view within this UIKit view controller
        let hostingController = UIHostingController(rootView: settingsView)
        
        // Add the hosting controller as a child
        addChild(hostingController)
        view.addSubview(hostingController.view)
        
        // Set up constraints to make the settings view fill the screen
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        hostingController.didMove(toParent: self)
    }


}

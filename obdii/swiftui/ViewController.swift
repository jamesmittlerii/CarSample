//
//  ViewController.swift
//  CarSample
//
//  Created by Alexander v. Below on 24.06.20.
//

import UIKit
import SwiftUI

class ViewController: UIViewController {

    private let carPlayPromptKey = "HasShownCarPlayDrivingPrompt"

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Create the SwiftUI root tab view
        let rootView = RootTabView()
        
        // Use a UIHostingController to embed the SwiftUI view within this UIKit view controller
        let hostingController = UIHostingController(rootView: rootView)
        
        // Add the hosting controller as a child
        addChild(hostingController)
        view.addSubview(hostingController.view)
        
        // Set up constraints to make the view fill the screen
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        hostingController.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Present the dialog once
        let hasShown = UserDefaults.standard.bool(forKey: carPlayPromptKey)
        if !hasShown {
            presentCarPlayDrivingPrompt()
            UserDefaults.standard.set(true, forKey: carPlayPromptKey)
        }
    }

    private func presentCarPlayDrivingPrompt() {
        let alert = UIAlertController(
            title: "Safety Reminder",
            message: "Do not change settings while driving.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        // Ensure we present on the main thread
        DispatchQueue.main.async { [weak self] in
            self?.present(alert, animated: true, completion: nil)
        }
    }
}

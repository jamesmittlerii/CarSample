//
//  AppDelegate.swift
//  CarSample
//
//  Created by Alexander v. Below on 24.06.20.
//

import UIKit
import OSLog


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    // Define an app-wide logger
    static let logger = Logger(subsystem: "com.rheosoft.obdii", category: "AppInit")

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // App-level setup only
        return true
    }
}

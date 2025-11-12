//
//  SceneDelegate.swift
//  CarSample
//
//  Created by Alexander v. Below on 24.06.20.
//

import UIKit

func deviceModelIdentifier() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    return String(bytes: Data(bytes: &systemInfo.machine,
                              count: Int(_SYS_NAMELEN)),
                  encoding: .ascii)?
        .trimmingCharacters(in: .controlCharacters) ?? "unknown"
}

func isRunningOniPadHardware() -> Bool {
    return deviceModelIdentifier().starts(with: "iPad")
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {

        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)

#if !DEBUG
        if UIDevice.current.userInterfaceIdiom == .pad || isRunningOniPadHardware() {
            window.rootViewController = UnsupportedDeviceViewController()
            self.window = window
            window.makeKeyAndVisible()
            return
        }
#endif

        // Normal root for supported devices (e.g., iPhone)
        window.rootViewController = ViewController()
        self.window = window
        window.makeKeyAndVisible()
    }
}

/// Simple placeholder screen shown on iPad in RELEASE builds.
/// Replace with your own implementation if desired.
final class UnsupportedDeviceViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = "This CarPlay enabled app is not supported on iPad."
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}

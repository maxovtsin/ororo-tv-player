//
//  AppDelegate.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import Transitions
import OroroKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    // MARK: - Properties
    private let coordinator = MainCoordinator()
    private let serviceProvider = ServiceProvider(
        credentials: Credentials(
            username: "test@example.com",
            password: "password"
        )
    )

    // MARK: - UIApplicationDelegate
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        coordinator.launch(
            rootFlowType: RootFlow.self,
            injection: RootFlow.Injection(
                serviceProvider: serviceProvider
            )
        )

        return true
    }
}

//
//  TransitionHandler.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit

protocol TransitionHandler: class {

    var tabBarViewController: UITabBarController { get }
    func present(viewController: UIViewController, modally: Bool)
}

extension TransitionHandler {

    func present(viewController: UIViewController, modally: Bool) {
        let currentViewController = tabBarViewController.selectedViewController as! UINavigationController
        if modally {
            currentViewController.present(viewController, animated: true, completion: nil)
        } else {
            currentViewController.pushViewController(viewController, animated: true)
        }
    }
}

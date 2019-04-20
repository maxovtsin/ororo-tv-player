//
//  UIViewController+Toast.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 16/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit

extension UIViewController {

    func showToast(title: String) {
        let alert = UIAlertController(title: title,
                                      message: title,
                                      preferredStyle: .alert)

        let close = UIAlertAction(title: "close".localized(),
                                  style: .cancel) { (_) in
                                    alert.dismiss(animated: true, completion: nil)
        }
        alert.addAction(close)
        present(alert, animated: true, completion: nil)
    }
}

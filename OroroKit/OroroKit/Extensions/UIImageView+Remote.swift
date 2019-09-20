//
//  UIImageView+Remote.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit

public extension UIImageView {

    // MARK: - Public interface
    func set(url: URL, placeholder: UIImage?) {
        image = placeholder
        dataTask = URLSession.shared.dataTask(with: url) { (data, _, _) in
            if let data = data {
                DispatchQueue.main.async(execute: {
                    self.image = UIImage(data: data)
                })
            }
        }
        dataTask?.resume()
    }

    func set(url: URL) {
        set(url: url, placeholder: nil)
    }

    func stopLoading() {
        dataTask?.cancel()
    }

    // MARK: - Inner type
    private struct AssociatedKeys {
        static var DescriptiveName = "data_task_associated_key"
    }

    // MARK: - Private members
    private var dataTask: URLSessionDataTask? {
        get {
            return objc_getAssociatedObject(self,
                                            &AssociatedKeys.DescriptiveName) as? URLSessionDataTask
        }
        set {
            objc_setAssociatedObject(self,
                                     &AssociatedKeys.DescriptiveName,
                                     newValue,
                                     .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

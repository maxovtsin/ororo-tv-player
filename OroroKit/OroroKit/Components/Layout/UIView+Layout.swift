//
//  UIView+Layout.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import Foundation
import UIKit

public extension UIView {

    @discardableResult
    func layout(builder: (UIView) -> Void) -> UIView {
        self.translatesAutoresizingMaskIntoConstraints = false
        builder(self)
        return self
    }

    @discardableResult
    func removeConstraints() -> UIView {
        precondition(superview != nil, "The view must be added to the view hierarchy")
        let constraintsToConsider = superview!.constraints + self.constraints
        constraintsToConsider
            .filter { ($0.firstItem as? UIView) == self }
            .forEach { $0.isActive = false }
        return self
    }

    @discardableResult
    func relayout(builder: (UIView) -> Void) -> UIView {
        return removeConstraints()
            .layout(builder: builder)
    }

    @discardableResult
    func pinToParent() -> UIView {
        return relayout { (v) in
            v.centerX <-> 0
            v.centerY <-> 0
            v.leading <-> 0
            v.top <-> 0
        }
    }
}

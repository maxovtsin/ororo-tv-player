//
//  ConstraintItem.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit

public final class ConstraintItem {

    // MARK: - Properties
    var target: Any
    var attribute: NSLayoutConstraint.Attribute

    // MARK: - Life cycle
    init(target: Any,
         attribute: NSLayoutConstraint.Attribute) {
        self.target = target
        self.attribute = attribute
    }

    var adjusted: AdjustedConstraintItem {
        return AdjustedConstraintItem(target: target,
                                      attribute: attribute,
                                      multiplier: 1,
                                      constant: 0)
    }
}

public final class AdjustedConstraintItem {

    // MARK: - Properties
    var target: Any?
    var attribute: NSLayoutConstraint.Attribute?
    var multiplier: CGFloat
    var constant: CGFloat

    // MARK: - Life cycle
    init(target: Any? = nil,
         attribute: NSLayoutConstraint.Attribute? = nil,
         multiplier: CGFloat = 1,
         constant: CGFloat = 0) {
        self.target = target
        self.attribute = attribute
        self.multiplier = multiplier
        self.constant = constant
    }
}

precedencegroup OperatorLeft {
    associativity: left
}

precedencegroup OperatorRight {
    associativity: right
}

public func <-> (source: ConstraintItem, dest: AdjustedConstraintItem) {
    let destTarget: Any? = dest.target ?? (source.target as? UIView)?.superview
    let destAttribute = dest.attribute ?? source.attribute

    let constraint = NSLayoutConstraint(
        item: source.target, attribute: source.attribute, relatedBy: .equal,
        toItem: destTarget, attribute: destAttribute,
        multiplier: dest.multiplier, constant: dest.constant)
    constraint.isActive = true
}

infix operator <-> : OperatorLeft
public func <-> (source: ConstraintItem, dest: ConstraintItem) {
    source <-> dest.adjusted
}

public func <-> (source: ConstraintItem, value: CGFloat) {
    switch source.attribute {
    case .width, .height:
        source <-> AdjustedConstraintItem(multiplier: 0,
                                          constant: value)
    case _:
        source <-> AdjustedConstraintItem(constant: value)
    }
}

public func + (item: AdjustedConstraintItem, value: CGFloat) -> AdjustedConstraintItem {
    return AdjustedConstraintItem(target: item.target,
                                  attribute: item.attribute,
                                  multiplier: item.multiplier,
                                  constant: item.constant + value)
}

public func + (item: ConstraintItem, value: CGFloat) -> AdjustedConstraintItem {
    return item.adjusted + value
}

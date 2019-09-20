//
//  UIView+ConstraintItem.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit

public extension UIView {

    var leading: ConstraintItem {
        return ConstraintItem(target: self, attribute: .leading)
    }

    var trailing: ConstraintItem {
        return ConstraintItem(target: self, attribute: .trailing)
    }

    var centerX: ConstraintItem {
        return ConstraintItem(target: self, attribute: .centerX)
    }

    var centerY: ConstraintItem {
        return ConstraintItem(target: self, attribute: .centerY)
    }

    var top: ConstraintItem {
        return ConstraintItem(target: self, attribute: .top)
    }

    var bottom: ConstraintItem {
        return ConstraintItem(target: self, attribute: .bottom)
    }

    var height: ConstraintItem {
        return ConstraintItem(target: self, attribute: .height)
    }

    var width: ConstraintItem {
        return ConstraintItem(target: self, attribute: .width)
    }
}

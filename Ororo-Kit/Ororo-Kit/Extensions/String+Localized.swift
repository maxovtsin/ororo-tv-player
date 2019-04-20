//
//  Localized.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 16/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import Foundation

public extension String {

    func localized(bundle: Bundle = .main,
                          tableName: String = "Localizable") -> String {
        return NSLocalizedString(self,
                                 tableName: tableName,
                                 value: self,
                                 comment: "")
    }
}

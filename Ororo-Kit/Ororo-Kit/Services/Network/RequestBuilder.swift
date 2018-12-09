//
//  RequestBuilder.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import Foundation

public enum HTTPMethod: String {
    case get
}

public struct Credentials {

    let username: String
    let password: String

    public init(username: String,
                password: String) {
        self.username = username
        self.password = password
    }
}

public final class RequestBuilder {

    // MARK: - Properties
    private let headers: [String: String]
    private let httpMethod: HTTPMethod
    private let credentials: Credentials?

    // MARK: - Life cycle
    public convenience init() {
        self.init(headers: [:])
    }

    public init(headers: [String: String],
                credentials: Credentials? = nil,
                httpMethod: HTTPMethod = .get) {
        self.headers = headers
        self.credentials = credentials
        self.httpMethod = httpMethod
    }

    // MARK: - Public interface
    func buildRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod.rawValue
        for header in headers {
            request.setValue(header.value,
                             forHTTPHeaderField: header.key)
        }

        if let credentials = credentials {
            if let data = "\(credentials.username):\(credentials.password)".data(using: .utf8) {
                let credential = data.base64EncodedString(options: [])
                request.setValue("Basic \(credential)",
                    forHTTPHeaderField: "Authorization")
            }
        }

        return request
    }
}

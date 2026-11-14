import Foundation
import OroroCore

public enum Endpoint: Sendable, Equatable {
    case shows, movies, show(Int), movie(Int), episode(Int)

    /// "/shows", "/shows/12", "/episodes/5", …
    public var path: String {
        switch self {
        case .shows: "/shows"
        case .movies: "/movies"
        case .show(let id): "/shows/\(id)"
        case .movie(let id): "/movies/\(id)"
        case .episode(let id): "/episodes/\(id)"
        }
    }
}

public struct RawResponse: Sendable {
    public let data: Data
    public let etag: String?
    public let notModified: Bool

    public init(data: Data, etag: String?, notModified: Bool) {
        self.data = data
        self.etag = etag
        self.notModified = notModified
    }
}

public struct Transport: Sendable {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = URL(string: "https://ororo.tv/api/v2")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func send(_ endpoint: Endpoint, credentials: Credentials, ifNoneMatch: String? = nil,
                     progress: (@Sendable (Double) -> Void)? = nil) async throws -> RawResponse {
        var request = URLRequest(url: URL(string: baseURL.absoluteString + endpoint.path)!)
        let token = Data("\(credentials.email):\(credentials.password)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        if let ifNoneMatch {
            request.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match")
        }

        let data: Data
        let response: URLResponse
        do {
            if let progress {
                (data, response) = try await download(request, progress: progress)
            } else {
                (data, response) = try await session.data(for: request)
            }
        } catch let error as URLError where Self.isOffline(error) {
            throw APIError.offline
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.decoding }
        let etag = http.value(forHTTPHeaderField: "ETag")
        switch http.statusCode {
        case 304: return RawResponse(data: Data(), etag: etag, notModified: true)
        case 200..<300: return RawResponse(data: data, etag: etag, notModified: false)
        case 401: throw APIError.unauthorized
        case 404: throw APIError.notFound
        default: throw APIError.server(status: http.statusCode)
        }
    }

    private func download(_ request: URLRequest,
                          progress: @Sendable (Double) -> Void) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        let expected = response.expectedContentLength
        var data = Data()
        var sinceReport = 0
        for try await byte in bytes {
            data.append(byte)
            sinceReport += 1
            if expected > 0, sinceReport >= 16 * 1024 {
                sinceReport = 0
                progress(min(1, Double(data.count) / Double(expected)))
            }
        }
        if expected > 0 { progress(min(1, Double(data.count) / Double(expected))) }
        return (data, response)
    }

    private static func isOffline(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet, .timedOut, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
            true
        default:
            false
        }
    }
}

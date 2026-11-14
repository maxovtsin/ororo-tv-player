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
        var request = URLRequest(url: baseURL.appending(path: endpoint.path))
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
        } catch let error as URLError {
            throw Self.map(error)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.server(status: 0) }
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
        if expected > 0 { data.reserveCapacity(Int(min(expected, 64 * 1024 * 1024))) }
        var chunk = [UInt8]()
        chunk.reserveCapacity(Self.chunkSize)
        for try await byte in bytes {
            chunk.append(byte)
            if chunk.count >= Self.chunkSize {
                data.append(contentsOf: chunk)
                chunk.removeAll(keepingCapacity: true)
                if expected > 0 { progress(min(1, Double(data.count) / Double(expected))) }
            }
        }
        data.append(contentsOf: chunk)
        if expected > 0 { progress(min(1, Double(data.count) / Double(expected))) }
        return (data, response)
    }

    private static let chunkSize = 64 * 1024

    /// Cancellation stays cancellation; connectivity failures are `.offline`; any other transport-level
    /// failure is `.server(status: 0)` (0 = no HTTP status, the request never completed).
    private static func map(_ error: URLError) -> Error {
        switch error.code {
        case .cancelled:
            CancellationError()
        case .notConnectedToInternet, .timedOut, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
             .dnsLookupFailed, .secureConnectionFailed, .internationalRoamingOff, .dataNotAllowed,
             .cannotLoadFromNetwork, .callIsActive:
            APIError.offline
        default:
            APIError.server(status: 0)
        }
    }
}

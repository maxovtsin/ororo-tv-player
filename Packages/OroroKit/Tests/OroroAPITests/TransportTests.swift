import Foundation
import Testing
import OroroCore
@testable import OroroAPI

/// Stub responses keyed by request host, so parallel tests never share state.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    enum Outcome: Sendable {
        case response(status: Int, headers: [String: String], body: Data)
        case failure(URLError.Code)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var outcomes: [String: Outcome] = [:]
    nonisolated(unsafe) private static var requests: [String: URLRequest] = [:]

    static func register(host: String, _ outcome: Outcome) {
        lock.lock(); defer { lock.unlock() }
        outcomes[host] = outcome
    }

    static func lastRequest(host: String) -> URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return requests[host]
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        Self.lock.lock()
        Self.requests[host] = request
        let outcome = Self.outcomes[host]
        Self.lock.unlock()
        switch outcome {
        case .response(let status, let headers, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
        }
    }

    override func stopLoading() {}
}

final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []
    func append(_ value: Double) { lock.lock(); storage.append(value); lock.unlock() }
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return storage }
}

@Suite struct TransportTests {
    private let credentials = Credentials(email: "user@example.com", password: "secret")

    private func make(_ outcome: StubProtocol.Outcome) -> (Transport, String) {
        let host = "t\(UUID().uuidString.prefix(8).lowercased()).test"
        StubProtocol.register(host: host, outcome)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let transport = Transport(baseURL: URL(string: "https://\(host)/api/v2")!, session: URLSession(configuration: config))
        return (transport, host)
    }

    private func ok(_ headers: [String: String] = [:], body: String = "{}") -> StubProtocol.Outcome {
        .response(status: 200, headers: headers, body: Data(body.utf8))
    }

    @Test func buildsURLAndBasicAuthHeader() async throws {
        let (transport, host) = make(ok())
        let creds = Credentials(email: "jürgen@example.com", password: "pä55")
        let response = try await transport.send(.show(12), credentials: creds)
        #expect(response.data == Data("{}".utf8))
        let request = try #require(StubProtocol.lastRequest(host: host))
        #expect(request.url?.path == "/api/v2/shows/12")
        let expected = Data("jürgen@example.com:pä55".utf8).base64EncodedString()
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic \(expected)")
    }

    @Test func sendsIfNoneMatch() async throws {
        let (transport, host) = make(ok())
        _ = try await transport.send(.shows, credentials: credentials, ifNoneMatch: "\"abc\"")
        #expect(StubProtocol.lastRequest(host: host)?.value(forHTTPHeaderField: "If-None-Match") == "\"abc\"")
        let (t2, h2) = make(ok())
        _ = try await t2.send(.shows, credentials: credentials)
        #expect(StubProtocol.lastRequest(host: h2)?.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test func returnsEtagFromHeader() async throws {
        let (transport, _) = make(ok(["ETag": "\"v1\""]))
        let response = try await transport.send(.movies, credentials: credentials)
        #expect(response.etag == "\"v1\"")
        #expect(response.notModified == false)
    }

    @Test func maps304ToNotModified() async throws {
        let (transport, _) = make(.response(status: 304, headers: [:], body: Data()))
        let response = try await transport.send(.shows, credentials: credentials, ifNoneMatch: "\"v1\"")
        #expect(response.notModified)
        #expect(response.data.isEmpty)
    }

    @Test func maps401() async {
        let (transport, _) = make(.response(status: 401, headers: [:], body: Data()))
        await #expect(throws: APIError.unauthorized) { try await transport.send(.shows, credentials: credentials) }
    }

    @Test func maps404() async {
        let (transport, _) = make(.response(status: 404, headers: [:], body: Data()))
        await #expect(throws: APIError.notFound) { try await transport.send(.movie(3), credentials: credentials) }
    }

    @Test func maps500ToServer() async {
        let (transport, _) = make(.response(status: 500, headers: [:], body: Data()))
        await #expect(throws: APIError.server(status: 500)) { try await transport.send(.shows, credentials: credentials) }
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .timedOut, .networkConnectionLost,
                      .cannotFindHost, .cannotConnectToHost])
    func mapsURLErrorToOffline(code: URLError.Code) async {
        let (transport, _) = make(.failure(code))
        await #expect(throws: APIError.offline) { try await transport.send(.shows, credentials: credentials) }
    }

    @Test func progressReportsFractionWhenLengthKnown() async throws {
        let body = String(repeating: "x", count: 100)
        let (transport, _) = make(ok(["Content-Length": "100"], body: body))
        let box = ProgressBox()
        let response = try await transport.send(.shows, credentials: credentials, progress: { box.append($0) })
        #expect(response.data.count == 100)
        #expect(box.values.last == 1.0)
        #expect(box.values.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    @Test func endpointPaths() {
        #expect(Endpoint.shows.path == "/shows")
        #expect(Endpoint.movies.path == "/movies")
        #expect(Endpoint.show(12).path == "/shows/12")
        #expect(Endpoint.movie(7).path == "/movies/7")
        #expect(Endpoint.episode(5).path == "/episodes/5")
    }
}

import Foundation
import Network
import Synchronization

/// An HTTP response produced by a `LoopbackServer` handler.
struct LoopbackResponse: Sendable {
    var status: Int
    var contentType: String
    var body: Data

    static let notFound = LoopbackResponse(status: 404, contentType: "text/plain", body: Data())
    static let badGateway = LoopbackResponse(status: 502, contentType: "text/plain", body: Data())
}

/// A tiny HTTP/1.1 server bound to `127.0.0.1` only. Every URL carries an unguessable per-server token; requests
/// without it never reach the handler. The token and port outlive a lost listener (`ensureListening()` re-listens
/// on both), so URLs already handed out stay valid. Never logs anything URL-like.
final class LoopbackServer: Sendable {
    typealias Handler = @Sendable (_ path: String) async -> LoopbackResponse

    private struct State {
        var listener: NWListener?
        var isReady = false
        var port: NWEndpoint.Port?
        var token = ""
        var isStopped = false
        var relisten: Task<Bool, Never>?
        var connections: [ObjectIdentifier: ClientConnection] = [:]
    }

    private static let maxHeadBytes = 16 * 1024
    private let handler: Handler
    private let queue = DispatchQueue(label: "ororo.loopback-server")
    private let state = Mutex(State())

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func start() async throws -> URL {
        let token = UUID().uuidString
        let listener = try await listen(on: nil)
        guard let port = listener.port else {
            listener.cancel()
            throw NWError.posix(.EADDRNOTAVAIL)
        }
        let stored: Bool = state.withLock {
            guard !$0.isStopped else { return false }
            $0.port = port
            $0.token = token
            return true
        }
        guard stored, adopt(listener) else {
            listener.cancel()
            throw CancellationError()
        }
        return URL(string: "http://127.0.0.1:\(port.rawValue)/\(token)/")!
    }

    func ensureListening() async -> Bool {
        // One re-listen at a time: concurrent callers await the same attempt.
        let task: Task<Bool, Never>? = state.withLock { (current: inout State) -> Task<Bool, Never>? in
            guard !current.isStopped, let port = current.port else { return nil }
            if current.isReady { return Task { true } }
            if let running = current.relisten { return running }
            let attempt = Task { [self] in
                let result = await relisten(on: port)
                self.state.withLock { $0.relisten = nil }
                return result
            }
            current.relisten = attempt
            return attempt
        }
        return await task?.value ?? false
    }

    /// Test hook: kills the live listener the way a backgrounded app loses it. Open connections are unaffected.
    func dropListenerForTesting() {
        let listener = state.withLock { state -> NWListener? in
            defer { state.listener = nil; state.isReady = false }
            return state.listener
        }
        listener?.cancel()
    }

    /// The OS may release the port a moment after the old listener died, so a few attempts are made.
    private func relisten(on port: NWEndpoint.Port) async -> Bool {
        for attempt in 0..<5 {
            if state.withLock({ $0.isStopped }) { return false }
            if let listener = try? await listen(on: port) {
                if adopt(listener) { return true }
                listener.cancel()
            }
            if attempt < 4 { try? await Task.sleep(for: .milliseconds(100)) }
        }
        return false
    }

    func stop() {
        let (listener, connections) = state.withLock { state -> (NWListener?, [ClientConnection]) in
            state.isStopped = true
            state.isReady = false
            let listener = state.listener
            state.listener = nil
            let connections = Array(state.connections.values)
            state.connections.removeAll()
            return (listener, connections)
        }
        listener?.cancel()
        connections.forEach { $0.close() }
    }

    // MARK: - Listening

    /// Creates a listener and waits until it is ready (or fails). `NWListener` is `Sendable`.
    private func listen(on port: NWEndpoint.Port?) async throws -> NWListener {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port ?? .any)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        let pending = Mutex<CheckedContinuation<Void, Error>?>(nil)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                pending.withLock { $0 = continuation }
                listener.stateUpdateHandler = { [weak self, weak listener] newState in
                    switch newState {
                    case .ready:
                        pending.withLock { $0.take() }?.resume()
                    case .failed(let error):
                        pending.withLock { $0.take() }?.resume(throwing: error)
                        if let listener { self?.listenerEnded(listener) }
                    case .waiting(let error):
                        // Not able to bind now: fail rather than leave the caller waiting.
                        pending.withLock { $0.take() }?.resume(throwing: error)
                        if let listener { self?.listenerEnded(listener) }
                    case .cancelled:
                        pending.withLock { $0.take() }?.resume(throwing: CancellationError())
                        if let listener { self?.listenerEnded(listener) }
                    default:
                        break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }
                listener.start(queue: queue)
            }
        } onCancel: {
            listener.cancel()
        }
        return listener
    }

    /// Makes `listener` the live one. Returns false (and cancels it) if the server was stopped meanwhile.
    @discardableResult
    private func adopt(_ listener: NWListener) -> Bool {
        let (adopted, previous) = state.withLock { state -> (Bool, NWListener?) in
            // A listener that already died (ready, then failed) before being stored must not look alive.
            guard !state.isStopped, listener.state == .ready else { return (false, nil) }
            let previous = state.listener
            state.listener = listener
            state.isReady = true
            return (true, previous)
        }
        previous?.cancel()
        if !adopted { listener.cancel() }
        return adopted
    }

    /// A listener failed or was cancelled: forget it (if it is the live one) and make sure it releases the port.
    private func listenerEnded(_ listener: NWListener) {
        state.withLock {
            if $0.listener === listener {
                $0.listener = nil
                $0.isReady = false
            }
        }
        listener.cancel()
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        let client = ClientConnection(connection: connection, queue: queue, maxHeadBytes: Self.maxHeadBytes)
        let key = ObjectIdentifier(client)
        let admitted = state.withLock { state -> Bool in
            guard !state.isStopped else { return false }
            state.connections[key] = client
            return true
        }
        guard admitted else {
            client.close()
            return
        }
        let handler = handler
        client.run(
            route: { [weak self] target in self?.route(target) ?? .reject(.notFound) },
            respond: handler,
            finished: { [weak self] in
                self?.state.withLock { _ = $0.connections.removeValue(forKey: key) }
            }
        )
    }

    private func route(_ target: String) -> ClientConnection.Route {
        let prefix = "/" + state.withLock { $0.token } + "/"
        guard target.hasPrefix(prefix) else { return .reject(.notFound) }
        var path = String(target.dropFirst(prefix.count))
        if let end = path.firstIndex(where: { $0 == "?" || $0 == "#" }) { path = String(path[..<end]) }
        return .handle(path.removingPercentEncoding ?? path)
    }

    /// A fixed ASCII reason phrase: never `HTTPURLResponse.localizedString`, which follows the device language.
    static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 502: "Bad Gateway"
        default: "Status"
        }
    }
}

/// One accepted connection: reads a request head, runs the handler, writes the response and closes.
private final class ClientConnection: Sendable {
    enum Route: Sendable {
        case reject(LoopbackResponse)
        case handle(String)
    }

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let maxHeadBytes: Int
    private let task = Mutex<Task<Void, Never>?>(nil)

    init(connection: NWConnection, queue: DispatchQueue, maxHeadBytes: Int) {
        self.connection = connection
        self.queue = queue
        self.maxHeadBytes = maxHeadBytes
    }

    func close() {
        task.withLock { $0?.cancel() }
        connection.cancel()
    }

    func run(route: @escaping @Sendable (String) -> Route,
             respond: @escaping LoopbackServer.Handler,
             finished: @escaping @Sendable () -> Void) {
        connection.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .failed, .cancelled:
                self?.task.withLock { $0?.cancel() }
                finished()
            default:
                break
            }
        }
        connection.start(queue: queue)
        readHead(Data()) { [weak self] head in
            guard let self else { return }
            guard let head, let target = Self.target(of: head.request, method: head.method) else {
                if let head, head.method != "GET" {
                    self.send(LoopbackResponse(status: 405, contentType: "text/plain", body: Data()))
                } else {
                    self.connection.cancel()
                }
                return
            }
            switch route(target) {
            case .reject(let response):
                self.send(response)
            case .handle(let path):
                self.watchForDisconnect()
                let work = Task { [weak self] in
                    let response = await respond(path)
                    guard !Task.isCancelled else { return }
                    self?.send(response)
                }
                self.task.withLock { $0 = work }
            }
        }
    }

    // MARK: - Request parsing

    private struct Head { var method: String; var request: [Substring] }

    private func readHead(_ buffer: Data, completion: @escaping @Sendable (Head?) -> Void) {
        let remaining = maxHeadBytes - buffer.count
        guard remaining > 0 else { return completion(nil) }
        connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headText = String(bytes: buffer[..<end.lowerBound], encoding: .utf8) ?? ""
                let parts = (headText.components(separatedBy: "\r\n").first ?? "")
                    .trimmingCharacters(in: .whitespaces).split(separator: " ")
                guard parts.count == 3, parts[2].hasPrefix("HTTP/") else { return completion(nil) }
                return completion(Head(method: String(parts[0]), request: parts))
            }
            if buffer.count >= self.maxHeadBytes || isComplete || error != nil { return completion(nil) }
            self.readHead(buffer, completion: completion)
        }
    }

    private static func target(of request: [Substring], method: String) -> String? {
        method == "GET" ? String(request[1]) : nil
    }

    // MARK: - Responding

    /// Once the head is read, any further inbound event (EOF, reset) means the client has gone away.
    private func watchForDisconnect() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] _, _, isComplete, error in
            guard let self else { return }
            if isComplete || error != nil {
                self.task.withLock { $0?.cancel() }
                self.connection.cancel()
            } else {
                self.watchForDisconnect()
            }
        }
    }

    private func send(_ response: LoopbackResponse) {
        var head = "HTTP/1.1 \(response.status) \(LoopbackServer.reasonPhrase(for: response.status))\r\n"
        head += "Content-Type: \(response.contentType)\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\n\r\n"
        var payload = Data(head.utf8)
        payload.append(response.body)
        connection.send(content: payload, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { [connection] _ in connection.cancel() })
    }
}

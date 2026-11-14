import Foundation
import Network
import Synchronization
@testable import OroroFeatures
import Testing

@Suite struct LoopbackServerTests {
    static func get(_ url: URL) async throws -> (status: Int, body: Data) {
        let (data, response) = try await URLSession(configuration: .ephemeral).data(from: url)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    private static let playlist = LoopbackResponse(
        status: 200, contentType: "application/vnd.apple.mpegurl", body: Data("#EXTM3U".utf8)
    )

    @Test func servesTheHandlerResponseUnderTheTokenPrefix() async throws {
        let server = LoopbackServer { $0 == "audio/0.m3u8" ? Self.playlist : .notFound }
        let base = try await server.start()
        defer { server.stop() }
        #expect(base.host() == "127.0.0.1" && base.absoluteString.hasSuffix("/"))
        let hit = try await Self.get(base.appending(path: "audio/0.m3u8"))
        #expect(hit.status == 200 && hit.body == Data("#EXTM3U".utf8))
        #expect(try await Self.get(base.appending(path: "nope")).status == 404)
    }

    @Test func rejectsRequestsWithoutTheToken() async throws {
        let server = LoopbackServer { _ in Self.playlist }
        let base = try await server.start()
        defer { server.stop() }
        let bare = try await Self.get(URL(string: "http://127.0.0.1:\(base.port!)/audio/0.m3u8")!)
        #expect(bare.status == 404 && bare.body.isEmpty)
    }

    @Test func servesLargeBodiesAndConcurrentRequests() async throws {
        let payload = Data((0..<600_000).map { UInt8(truncatingIfNeeded: $0) })
        let server = LoopbackServer { _ in LoopbackResponse(status: 200, contentType: "audio/mp4", body: payload) }
        let base = try await server.start()
        defer { server.stop() }
        try await withThrowingTaskGroup(of: Data.self) { group in
            for index in 0..<8 { group.addTask { try await Self.get(base.appending(path: "audio/0/\(index).m4s")).body } }
            for try await body in group { #expect(body == payload) }
        }
    }

    @Test func cancelsTheHandlerWhenTheClientGoesAway() async throws {
        let cancelled = AsyncStream<Void>.makeStream()
        let started = AsyncStream<Void>.makeStream()
        let server = LoopbackServer { _ in
            started.continuation.yield()
            do { try await Task.sleep(for: .seconds(30)) } catch { cancelled.continuation.yield() }
            return .notFound
        }
        let base = try await server.start()
        defer { server.stop() }
        let request = Task { try await Self.get(base.appending(path: "audio/0/0.m4s")) }
        var startedIterator = started.stream.makeAsyncIterator()
        await startedIterator.next()
        request.cancel()
        var iterator = cancelled.stream.makeAsyncIterator()
        await iterator.next() // the test times out if the handler is never cancelled
    }

    @Test func stopsListeningAndStaysStopped() async throws {
        let server = LoopbackServer { _ in .notFound }
        let base = try await server.start()
        #expect(await server.ensureListening())
        server.stop()
        var refused = false
        for _ in 0..<20 where !refused {
            do { _ = try await Self.get(base.appending(path: "x")) } catch { refused = true }
            if !refused { try await Task.sleep(for: .milliseconds(50)) }
        }
        #expect(refused)
        #expect(await server.ensureListening() == false)
    }

    @Test func listensAgainOnTheSamePortAndTokenAfterTheListenerDies() async throws {
        let server = LoopbackServer { _ in Self.playlist }
        let base = try await server.start()
        defer { server.stop() }
        server.dropListenerForTesting()
        #expect(await server.ensureListening())
        let hit = try await Self.get(base.appending(path: "audio/0.m3u8"))
        #expect(hit.status == 200 && hit.body == Data("#EXTM3U".utf8))
    }

    @Test func concurrentRelistenCallsBothSucceed() async throws {
        let server = LoopbackServer { _ in Self.playlist }
        let base = try await server.start()
        defer { server.stop() }
        server.dropListenerForTesting()
        async let first = server.ensureListening()
        async let second = server.ensureListening()
        let results = await [first, second]
        #expect(results == [true, true])
        #expect(try await Self.get(base.appending(path: "x")).status == 200)
    }

    /// Sends one raw request and returns the response's status line, byte for byte.
    private static func rawStatusLine(_ url: URL) async -> Data {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(url.port!))!, using: .tcp)
        connection.start(queue: .global())
        defer { connection.cancel() }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            connection.send(content: Data("GET \(url.path()) HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8),
                            completion: .contentProcessed { _ in done.resume() })
        }
        var received = Data()
        while received.range(of: Data("\r\n".utf8)) == nil {
            let chunk: Data? = await withCheckedContinuation { done in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                    done.resume(returning: data.flatMap { $0.isEmpty ? nil : $0 } ?? (isComplete || error != nil ? nil : Data()))
                }
            }
            guard let chunk else { break }
            received.append(chunk)
        }
        guard let end = received.range(of: Data("\r\n".utf8)) else { return received }
        return received[..<end.lowerBound]
    }

    @Test func statusLinesUseFixedASCIIReasonPhrases() async throws {
        let server = LoopbackServer { $0 == "audio/0.m3u8" ? Self.playlist : .notFound }
        let base = try await server.start()
        defer { server.stop() }
        #expect(await Self.rawStatusLine(base.appending(path: "audio/0.m3u8")) == Data("HTTP/1.1 200 OK".utf8))
        #expect(await Self.rawStatusLine(base.appending(path: "nope")) == Data("HTTP/1.1 404 Not Found".utf8))
        #expect(LoopbackServer.reasonPhrase(for: 502) == "Bad Gateway")
        #expect(LoopbackServer.reasonPhrase(for: 405) == "Method Not Allowed")
        let fallback = LoopbackServer.reasonPhrase(for: 500)
        #expect(fallback.allSatisfy { $0.isASCII })
    }

    @Test func closesConnectionsWhoseHeadExceedsTheLimitAcrossChunks() async throws {
        let calls = Mutex(0)
        let server = LoopbackServer { _ in
            calls.withLock { $0 += 1 }
            return Self.playlist
        }
        let base = try await server.start()
        defer { server.stop() }
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(base.port!))!, using: .tcp)
        connection.start(queue: .global())
        defer { connection.cancel() }
        let first = Data("GET \(base.path())".utf8) + Data(repeating: UInt8(ascii: "a"), count: 10_000)
        let second = Data(repeating: UInt8(ascii: "b"), count: 7_000) + Data(" HTTP/1.1\r\n\r\n".utf8)
        for chunk in [first, second] {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                connection.send(content: chunk, completion: .contentProcessed { _ in done.resume() })
            }
        }
        let received: Data = await withCheckedContinuation { done in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                done.resume(returning: data ?? Data())
            }
        }
        #expect(received.isEmpty)
        #expect(calls.withLock { $0 } == 0)
    }
}

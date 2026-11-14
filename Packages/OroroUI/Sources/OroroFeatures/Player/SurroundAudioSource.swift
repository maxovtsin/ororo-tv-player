import Foundation
import OroroCore
import os
import Synchronization

/// Why simulated surround gave up after playback started; the player then falls back to the original audio.
enum SurroundFailure: Sendable, Equatable {
    /// A segment could not be parsed or transcoded.
    case format
    /// Segments are taking longer than real time to deliver.
    case starved
    /// Transcoding alone takes more than half real time.
    case slowDevice
}

/// What the player engine needs from a surround audio source.
protocol SurroundSource: Sendable {
    /// Starts serving and returns the loopback base URL (ends with `/`).
    func start() async throws -> URL
    /// The pre-flight: the multivariant playlist re-pointed at local 5.1 renditions, or `nil` to leave it untouched.
    func author(multivariant: String) async -> String?
    /// Re-listens if the loopback listener was lost (for example while the app was in the background).
    func ensureServing() async -> Bool
    nonisolated func stop()
}

/// Transcodes one segment's stereo packets to 5.1 (see `SurroundTranscoder.transcode`).
typealias SurroundTranscode = @Sendable (_ previous: [Data], _ current: [Data], _ next: [Data], _ startFrame: Int) throws -> [Data]

/// Serves a title's audio as simulated 5.1 from the in-app loopback server.
///
/// `author(multivariant:)` checks the audio before the player sees anything: every rendition's media playlist, init
/// segment and first segment must be fetchable and supported. Afterwards each local segment request fetches the
/// original segment and its neighbours, transcodes it off the actor and rebuilds it. The source watches its own
/// timing and reports one `SurroundFailure` when the device is too slow or the player is being starved.
/// Keeps everything in memory and never logs or exposes an origin URL.
actor SurroundAudioSource: SurroundSource {
    private static let log = Logger(subsystem: "com.dissimirall.Ororo-Player", category: "Surround")
    private static let playlistType = "application/vnd.apple.mpegurl", segmentType = "audio/mp4"
    private static let parsedCapacity = 8, generatedCapacity = 4, transcodeSlots = 2

    private struct Rendition {
        var playlist: Data
        var initSegment: Data
        var segments: [URL]
    }

    private struct SegmentKey: Hashable {
        var rendition: Int
        var index: Int
    }

    private struct Generated {
        var body: Data
        var transcode: Duration
        var packets: Int
    }

    private enum Outcome {
        case segment(Generated)
        case notFound, transport, format, cancelled
    }

    /// One shared generation of a segment, abandoned when every request waiting for it is cancelled.
    private struct Generation {
        var id: UUID
        var task: Task<Outcome, Never>
        var waiters: Int
    }

    private struct ServerSlot {
        var server: LoopbackServer?
        var isStopped = false
    }

    private let fetch: SubtitleResourceResponder.ResolvingFetch
    private let transcode: SurroundTranscode
    private let now: @Sendable () -> ContinuousClock.Instant
    private let onFailure: @Sendable (SurroundFailure) -> Void
    private let slot = Mutex(ServerSlot())

    private var base: URL?
    private var renditions: [Rendition] = []
    private var parsed = RecentCache<SegmentKey, FragmentedMP4.AudioFragment>(capacity: parsedCapacity)
    private var generated = RecentCache<SegmentKey, Generated>(capacity: generatedCapacity)
    private var generating: [SegmentKey: Generation] = [:]
    private var freeSlots = transcodeSlots
    private var slotWaiters: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []
    private var health = SurroundHealth()
    private var hasFailed = false

    init(fetch: @escaping SubtitleResourceResponder.ResolvingFetch = SubtitleResourceLoader.download,
         transcode: @escaping SurroundTranscode = SurroundAudioSource.liveTranscode(signal: nil),
         now: @escaping @Sendable () -> ContinuousClock.Instant = { .now },
         onFailure: @escaping @Sendable (SurroundFailure) -> Void) {
        self.fetch = fetch
        self.transcode = transcode
        self.now = now
        self.onFailure = onFailure
    }

    static func liveTranscode(signal: SurroundDebugSignal?) -> SurroundTranscode {
        let transcoder = SurroundTranscoder(signal: signal)
        return { previous, current, next, startFrame in
            try transcoder.transcode(previous: previous, current: current, next: next, startFrame: startFrame)
        }
    }

    // MARK: - Serving

    func start() async throws -> URL {
        if let base { return base }
        let server = LoopbackServer { [weak self] path in
            await self?.respond(to: path) ?? .notFound
        }
        let admitted = slot.withLock { slot -> Bool in
            guard !slot.isStopped, slot.server == nil else { return false }
            slot.server = server
            return true
        }
        guard admitted else { throw CancellationError() }
        let url = try await server.start()
        base = url
        return url
    }

    func ensureServing() async -> Bool {
        guard let server = slot.withLock({ $0.isStopped ? nil : $0.server }) else { return false }
        return await server.ensureListening()
    }

    nonisolated func stop() {
        let server = slot.withLock { slot -> LoopbackServer? in
            slot.isStopped = true
            return slot.server
        }
        server?.stop()
    }

    // MARK: - Pre-flight

    func author(multivariant: String) async -> String? {
        guard let base else { return decline(.notStarted) }
        guard let authored = SurroundPlaylistBuilder.multivariant(absolutised: multivariant, localBase: base) else {
            return decline(.layout)
        }
        var prepared: [Prepared] = []
        for (rendition, source) in authored.sources.enumerated() {
            switch await Self.prepare(source: source, rendition: rendition, base: base, fetch: fetch) {
            case .success(let result): prepared.append(result)
            case .failure(let reason): return decline(reason)
            }
        }
        renditions = prepared.map { Rendition(playlist: $0.playlist, initSegment: $0.initSegment, segments: $0.segments) }
        parsed.removeAll()
        generated.removeAll()
        for (rendition, result) in prepared.enumerated() {
            parsed.insert(result.first, for: SegmentKey(rendition: rendition, index: 0))
        }
        Self.log.notice("Surround accepted: \(prepared.count) rendition(s)")
        return authored.text
    }

    private func decline(_ reason: Decline) -> String? {
        Self.log.notice("Surround declined: \(reason.rawValue, privacy: .public)")
        return nil
    }

    // MARK: - Responding

    func respond(to path: String) async -> LoopbackResponse {
        switch SurroundPlaylistBuilder.resource(forPath: path) {
        case .playlist(let rendition) where renditions.indices.contains(rendition):
            return LoopbackResponse(status: 200, contentType: Self.playlistType, body: renditions[rendition].playlist)
        case .initSegment(let rendition) where renditions.indices.contains(rendition):
            return LoopbackResponse(status: 200, contentType: Self.segmentType, body: renditions[rendition].initSegment)
        case .segment(let rendition, let index) where renditions.indices.contains(rendition)
            && renditions[rendition].segments.indices.contains(index):
            return await segment(SegmentKey(rendition: rendition, index: index))
        default:
            return .notFound
        }
    }

    private func segment(_ key: SegmentKey) async -> LoopbackResponse {
        let started = now()
        let outcome: Outcome
        if var cached = generated.value(for: key) {
            cached.transcode = .zero
            outcome = .segment(cached)
        } else {
            outcome = await join(key)
        }
        // A cancelled request's response is never delivered and never counts.
        guard !Task.isCancelled else { return .notFound }
        switch outcome {
        case .segment(let result):
            if !hasFailed, let failure = health.record(transcode: result.transcode, total: now() - started, packets: result.packets) {
                report(failure)
            }
            return LoopbackResponse(status: 200, contentType: Self.segmentType, body: result.body)
        case .transport:
            return .badGateway
        case .format:
            report(.format)
            return .notFound
        case .notFound, .cancelled:
            return .notFound
        }
    }

    /// Waits for the segment's generation, starting one unless a request for it is already in flight.
    private func join(_ key: SegmentKey) async -> Outcome {
        let generation: Generation
        if var existing = generating[key] {
            existing.waiters += 1
            generating[key] = existing
            generation = existing
        } else {
            let id = UUID()
            generation = Generation(id: id, task: Task { await self.generate(key, id: id) }, waiters: 1)
            generating[key] = generation
        }
        let id = generation.id
        return await withTaskCancellationHandler {
            await generation.task.value
        } onCancel: {
            Task { await self.leave(key, id: id) }
        }
    }

    private func leave(_ key: SegmentKey, id: UUID) {
        guard var generation = generating[key], generation.id == id else { return }
        generation.waiters -= 1
        if generation.waiters > 0 {
            generating[key] = generation
        } else {
            generating[key] = nil
            generation.task.cancel()
        }
    }

    private func report(_ failure: SurroundFailure) {
        guard !hasFailed else { return }
        hasFailed = true
        Self.log.notice("Surround failed: \(String(describing: failure), privacy: .public)")
        onFailure(failure)
    }

    // MARK: - Generating

    /// A segment's own fragment and whichever neighbours exist; `complete` is false when one could not be fetched.
    private struct Neighbourhood {
        var previous: FragmentedMP4.AudioFragment?
        var current: FragmentedMP4.AudioFragment
        var next: FragmentedMP4.AudioFragment?
        var complete: Bool
    }

    private enum Gathered {
        case ready(Neighbourhood)
        case stopped(Outcome)
    }

    private func generate(_ key: SegmentKey, id: UUID) async -> Outcome {
        defer { if generating[key]?.id == id { generating[key] = nil } }
        let started = now()
        let fragments: Neighbourhood
        switch await gather(key) {
        case .ready(let gathered): fragments = gathered
        case .stopped(let outcome): return outcome
        }
        let current = fragments.current
        let job = TranscodeJob(
            previous: Array(fragments.previous?.packets.suffix(SurroundFormat.prerollPackets) ?? []),
            current: current.packets,
            next: Array(fragments.next?.packets.prefix(SurroundFormat.postrollPackets) ?? []),
            startFrame: Int(clamping: current.baseDecodeTime)
        )
        guard await acquireSlot() else { return .cancelled }
        defer { releaseSlot() }
        if Task.isCancelled { return .cancelled }
        guard let transcoded = try? await Self.run(job, transcode: transcode, now: now),
              transcoded.packets.count == current.packets.count else { return .format }

        let body = FragmentedMP4.buildAudioSegment(
            sequence: UInt32(clamping: key.index + 1),
            fragment: FragmentedMP4.AudioFragment(trackID: current.trackID, baseDecodeTime: current.baseDecodeTime,
                                                  packets: transcoded.packets)
        )
        let result = Generated(body: body, transcode: transcoded.elapsed, packets: current.packets.count)
        // Made without a neighbour that exists: served, but not kept, so a later request can do better.
        if fragments.complete { generated.insert(result, for: key) }
        Self.log.debug("""
            Surround segment \(key.rendition):\(key.index): \(result.packets) packets, \
            transcode \(Self.milliseconds(transcoded.elapsed)) ms, total \(Self.milliseconds(self.now() - started)) ms
            """)
        return .segment(result)
    }

    /// Segments `n − 1`, `n` and `n + 1` that exist: from the cache, or fetched in parallel and parsed.
    private func gather(_ key: SegmentKey) async -> Gathered {
        guard renditions.indices.contains(key.rendition) else { return .stopped(.notFound) }
        let urls = renditions[key.rendition].segments
        var fragments: [Int: FragmentedMP4.AudioFragment] = [:], missing: [Int: URL] = [:]
        for index in key.index - 1...key.index + 1 where urls.indices.contains(index) {
            fragments[index] = parsed.value(for: SegmentKey(rendition: key.rendition, index: index))
            if fragments[index] == nil { missing[index] = urls[index] }
        }
        let fetch = fetch
        let loaded = await withTaskGroup(of: (index: Int, loaded: Loaded).self) { group in
            for (index, url) in missing {
                group.addTask { (index, await Self.load(url, fetch: fetch)) }
            }
            return await group.reduce(into: [Int: Loaded]()) { $0[$1.index] = $1.loaded }
        }
        if Task.isCancelled { return .stopped(.cancelled) }

        var complete = true
        // The segment itself first, so its own transport error wins over a neighbour's parse error.
        for (index, result) in loaded.sorted(by: { ($0.key == key.index ? 0 : 1) < ($1.key == key.index ? 0 : 1) }) {
            switch result {
            case .fragment(let fragment):
                fragments[index] = fragment
                parsed.insert(fragment, for: SegmentKey(rendition: key.rendition, index: index))
            case .transport where index == key.index: return .stopped(.transport)
            case .transport: complete = false
            case .malformed: return .stopped(.format)
            case .cancelled: return .stopped(.cancelled)
            }
        }
        guard let current = fragments[key.index] else { return .stopped(.notFound) }
        return .ready(Neighbourhood(previous: fragments[key.index - 1], current: current, next: fragments[key.index + 1],
                                    complete: complete))
    }

    // MARK: - Transcode slots

    /// Waits for one of the `transcodeSlots`; `false` if the task was cancelled while waiting.
    private func acquireSlot() async -> Bool {
        if freeSlots > 0 {
            freeSlots -= 1
            return true
        }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else {
                    slotWaiters.append((id, continuation))
                }
            }
        } onCancel: {
            Task { await self.abandonSlotWait(id) }
        }
    }

    private func abandonSlotWait(_ id: UUID) {
        guard let index = slotWaiters.firstIndex(where: { $0.id == id }) else { return }
        slotWaiters.remove(at: index).continuation.resume(returning: false)
    }

    /// Hands the slot straight to the next waiter, if any.
    private func releaseSlot() {
        if slotWaiters.isEmpty {
            freeSlots += 1
        } else {
            slotWaiters.removeFirst().continuation.resume(returning: true)
        }
    }
}

// MARK: - Off-actor work

extension SurroundAudioSource {
    /// Why the pre-flight declined; logged as a category, never with a URL.
    private enum Decline: String, Error {
        case notStarted, layout, playlist, transport, format, cancelled
    }

    private struct Prepared: Sendable {
        var playlist: Data
        var initSegment: Data
        var segments: [URL]
        var first: FragmentedMP4.AudioFragment
    }

    private enum Loaded: Sendable {
        case fragment(FragmentedMP4.AudioFragment)
        case transport, malformed, cancelled
    }

    private struct TranscodeJob: Sendable {
        var previous: [Data]
        var current: [Data]
        var next: [Data]
        var startFrame: Int
    }

    private struct Transcoded: Sendable {
        var packets: [Data]
        var elapsed: Duration
    }

    /// Fetches and checks one rendition's media playlist (rewritten against its redirected URL), init and first segment.
    @concurrent private static func prepare(
        source: URL, rendition: Int, base: URL, fetch: SubtitleResourceResponder.ResolvingFetch
    ) async -> Result<Prepared, Decline> {
        let playlist: (data: Data, url: URL)
        do {
            playlist = try await fetch(source)
        } catch {
            return .failure(Task.isCancelled ? .cancelled : .transport)
        }
        guard let original = String(bytes: playlist.data, encoding: .utf8),
              let media = SurroundPlaylistBuilder.mediaPlaylist(
                original: original, originalURL: playlist.url, localBase: base, rendition: rendition
              ) else { return .failure(.playlist) }
        let initData: Data, firstData: Data
        do {
            async let initFetch = fetch(media.initURL)
            async let firstFetch = fetch(media.segments[0])
            initData = try await initFetch.data
            firstData = try await firstFetch.data
        } catch {
            return .failure(Task.isCancelled ? .cancelled : .transport)
        }
        do {
            let initSegment = try FragmentedMP4.surroundInitSegment(from: initData)
            let first = try FragmentedMP4.parseAudioSegment(firstData)
            return .success(Prepared(playlist: Data(media.text.utf8), initSegment: initSegment, segments: media.segments, first: first))
        } catch {
            return .failure(.format)
        }
    }

    @concurrent private static func load(_ url: URL, fetch: SubtitleResourceResponder.ResolvingFetch) async -> Loaded {
        let data: Data
        do {
            data = try await fetch(url).data
        } catch {
            return Task.isCancelled || error is CancellationError ? .cancelled : .transport
        }
        guard let fragment = try? FragmentedMP4.parseAudioSegment(data) else { return .malformed }
        return .fragment(fragment)
    }

    /// CPU work of tens to hundreds of milliseconds: never on the actor.
    @concurrent private static func run(
        _ job: TranscodeJob, transcode: SurroundTranscode, now: @Sendable () -> ContinuousClock.Instant
    ) async throws -> Transcoded {
        let started = now()
        let packets = try transcode(job.previous, job.current, job.next, job.startFrame)
        return Transcoded(packets: packets, elapsed: now() - started)
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        return Int(components.seconds) * 1000 + Int(components.attoseconds / 1_000_000_000_000_000)
    }
}

/// Judges the last few completed segment requests, each against its own duration.
struct SurroundHealth {
    static let window = 5, threshold = 3

    private struct Sample {
        var slow: Bool
        var starved: Bool
    }

    private var samples: [Sample] = []

    /// Records one request; returns the failure it reveals, `slowDevice` before `starved`.
    mutating func record(transcode: Duration, total: Duration, packets: Int) -> SurroundFailure? {
        guard packets > 0 else { return nil }
        let seconds = Double(packets * SurroundFormat.framesPerPacket) / SurroundFormat.sampleRate
        samples.append(Sample(slow: transcode > .seconds(seconds * 0.5), starved: total > .seconds(seconds)))
        if samples.count > Self.window { samples.removeFirst(samples.count - Self.window) }
        if samples.count(where: \.slow) >= Self.threshold { return .slowDevice }
        if samples.count(where: \.starved) >= Self.threshold { return .starved }
        return nil
    }
}

/// A tiny most-recently-used cache; the least recently used entry goes first.
private struct RecentCache<Key: Hashable, Value> {
    let capacity: Int
    private var order: [Key] = []
    private var values: [Key: Value] = [:]

    init(capacity: Int) {
        self.capacity = capacity
    }

    mutating func value(for key: Key) -> Value? {
        guard let value = values[key] else { return nil }
        touch(key)
        return value
    }

    mutating func insert(_ value: Value, for key: Key) {
        values[key] = value
        touch(key)
        while order.count > capacity {
            values[order.removeFirst()] = nil
        }
    }

    mutating func removeAll() {
        order.removeAll()
        values.removeAll()
    }

    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}

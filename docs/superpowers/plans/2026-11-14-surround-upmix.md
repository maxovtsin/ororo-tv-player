# Simulated 5.1 Surround Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** During Ororo playback on a 5.1 output, replace the stream's stereo audio with a 5.1 track the tvOS app generates on the fly, so the Sony HT-RT4's centre, rear speakers and subwoofer play.

**Architecture:** The app already serves AVPlayer a synthetic multivariant playlist to inject subtitles. That playlist's audio groups are re-pointed at a loopback HTTP server inside the app. For each audio segment the server fetches the original fMP4, decodes the stereo AAC, upmixes to six channels, re-encodes as 5.1 AAC and repackages it as fMP4. Pure pieces (fMP4, playlist authoring, upmix DSP, debug signals) live in `OroroCore/Playback`; the converter, server and wiring live in `OroroFeatures/Player`. Unsupported audio is detected before the player sees the playlist; a later audio-path failure makes the session reload the title with original audio.

**Tech Stack:** Swift 6.4 (language mode 6, strict concurrency), AVFoundation (`AVPlayer`, `AVAudioConverter`), Network.framework (`NWListener`), Swift Testing. Xcode 27.2, tvOS 26.

**Spec:** `docs/superpowers/specs/2026-11-14-surround-upmix-design.md` (revised after review; read its *Review findings* section).

**Revision 2 (2026-11-14):** rewritten after four independent reviews. Facts marked *measured* below come from an experiment run during that review, not from assumption.

## Global Constraints

- Deployment target tvOS 26 / iOS 26; `OroroKit` also builds for macOS 26 so `swift test` works. Swift 6 language mode in both packages.
- No new third-party dependency. No CI workflow or other infrastructure.
- Never log, persist or expose the signed stream URL, or any URL derived from it (the signature is in the query: keep the query when fetching, never print it). Errors that reach AVFoundation or logs carry no URL (follow `SubtitleResourceLoader.urlFree`).
- tvOS only. On iOS the surround policy is always "not wanted" and audio is the original.
- No system or receiver setting is changed; no behaviour outside Ororo playback changes; no copy tells the user to change an Apple TV setting.
- Audio stays within ±20 ms of where the original audio would be.
- A failure in the audio path never produces an error screen.
- Tests use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`). One test file per source file.
- `swiftlint lint --strict` must stay clean: line length 150, no tuples of more than two members (return structs), file length 1000.
- Logging uses `Logger(subsystem: "com.dissimirall.Ororo-Player", category: "Surround")` (the app's existing subsystem).
- Work on branch `feat/surround-upmix` (rename the current `spike/surround-upmix`). Each task ends by staging exactly the files it created or modified and committing; never push; never commit to `master`.

Commands used below:

| Alias | Command |
|---|---|
| `KIT_TEST <Suite>` | `swift test --package-path Packages/OroroKit --filter <Suite>` |
| `UI_TEST <Suite>` | `cd Packages/OroroUI && xcodebuild test -scheme OroroUI-Package -destination 'platform=tvOS Simulator,name=Apple TV 4K (4th generation)' -only-testing:OroroFeaturesTests/<Suite>` |
| `UI_BUILD_IOS` | `cd Packages/OroroUI && xcodebuild build -scheme OroroUI-Package -destination 'generic/platform=iOS Simulator'` |
| `LINT` | `swiftlint lint --strict` (repo root) |

Shared constants, `public enum SurroundFormat` (Task 1):

| Name | Type | Value | Meaning |
|---|---|---|---|
| `sampleRate` | `Double` | `48_000` | only rate supported |
| `framesPerPacket` | `Int` | `1024` | AAC-LC frame length; anything else is unsupported |
| `channelCount` | `Int` | `6` | order C L R Ls Rs LFE (`kAudioChannelLayoutTag_MPEG_5_1_D`, AAC channel configuration 6) |
| `bitRate` | `Int` | `384_000` | encoder setting (*measured* average output ≈ 394 kb/s) |
| `addedBitsPerSecond` | `Int` | `384_000` | flat addition to every variant's `BANDWIDTH` and `AVERAGE-BANDWIDTH` |
| `prerollPackets` | `Int` | `4` | previous-segment packets fed before the current segment (*measured* minimum 2) |
| `postrollPackets` | `Int` | `2` | next-segment packets fed after it (*measured* exact minimum 2) |
| `encoderDelayPackets` | `Int` | `2` | output packets dropped; *measured* encoder delay 2112 frames, leaving a constant 64-frame lag |
| `outputLagFrames` | `Int` | `64` | that remaining lag |
| `lfeGain` | `Float` | `0.1` | −20 dB; the receiver's bass management feeds the subwoofer |

## Review Focus

1. **Audio that is not "one continuous VOD playlist of unencrypted fMP4 stereo AAC-LC, 48 kHz, 1024-frame packets"** (muxed, `EXT-X-KEY`, `enca`, byte-range, discontinuity, live, already multichannel whether declared or not, mono, HE-AAC with 2048-frame packets, 44.1 kHz): the playlist is left untouched and the title plays original audio with no reload. Tests in Tasks 1, 2 and 6.
2. **Ends and odd sizes** (first and last segment of the title, a seek with no cached neighbour, a neighbour of 1–3 packets, a current segment of 1–2 packets): exactly one output packet per input packet, no throw, joins at codec-noise level. Tests in Task 4.
3. **A library saved before this feature** (no `simulatedSurround` key): the whole library decodes intact with surround on. Tests in Task 11.
4. **Output with fewer than 6 channels at load, and iOS**: original audio, no loopback server started. Tests in Task 7.
5. **Things arriving at the wrong time**: an unknown path, wrong token or out-of-range segment (404, no fallback); a transient origin error (502, no fallback); the same segment requested concurrently (one transcode); a failure reported by a previous title's source, or after the player was stopped (ignored). Tests in Tasks 5, 6 and 8.

---

### Task 1: fMP4 audio parsing, rebuilding and the 5.1 init segment

**Files:**
- Create: `Packages/OroroKit/Sources/OroroCore/Playback/SurroundFormat.swift`
- Create: `Packages/OroroKit/Sources/OroroCore/Playback/FragmentedMP4.swift`
- Create: `Packages/OroroKit/Tests/OroroTestSupport/HLSAudioFixture.swift`
- Create: `Packages/OroroKit/Tests/OroroTestSupport/MP4Bytes.swift`
- Test: `Packages/OroroKit/Tests/OroroCoreTests/FragmentedMP4Tests.swift`

**Interfaces:**
- Produces:
  - `public enum SurroundFormat` with the constants in the table above, exactly those names and types.
  - `public enum FragmentedMP4`:
    - `struct AudioFragment: Equatable, Sendable { public var trackID: UInt32; public var baseDecodeTime: UInt64; public var packets: [Data] }` (frame duration is always 1024: anything else is rejected)
    - `enum Failure: Error, Equatable { case malformed, unsupported }`
    - `static func parseAudioSegment(_ data: Data) throws -> AudioFragment`
    - `static func buildAudioSegment(sequence: UInt32, fragment: AudioFragment) -> Data`
    - `static func surroundInitSegment(from stereoInit: Data) throws -> Data`
  - Test support, `public struct HLSAudioFixture: Sendable { public var initSegment: Data; public var segments: [Data]; public var left: [Float]; public var right: [Float]; public static func make(seconds: Double, channels: Int = 2, sampleRate: Double = 48_000) async throws -> HLSAudioFixture }`.
    Signal, exactly: both channels carry a 60 Hz sine at 0.2; left adds 440 Hz at 0.2, right adds 660 Hz at 0.2; each channel adds independent white noise at ±0.05 from a SplitMix64 generator seeded 1 (left) and 2 (right); every 0.5 s a 5 ms burst of ±0.5 noise on the left only (transients near segment joins). Written with `AVAssetWriter` (`outputContentType = .mpeg4Movie`, `outputFileTypeProfile = .mpeg4AppleHLS`, `preferredOutputSegmentInterval` 2 s, AAC-LC at 128 kb/s), segments collected from the writer delegate. Feed the writer from a single task with a polling loop on `isReadyForMoreMediaData` (the `requestMediaDataWhenReady` closure would capture non-Sendable objects).
  - Test support, `public enum MP4Bytes`: `static func box(_ type: String, _ payload: Data) -> Data`, `static func be32(_ value: UInt32) -> Data`, `static func be64(_ value: UInt64) -> Data`, for hand-building fixtures.

- [ ] **Step 1: Rename the branch**

Run: `git branch -m spike/surround-upmix feat/surround-upmix`

- [ ] **Step 2: Write the fixtures and the failing tests**

```swift
@Suite struct FragmentedMP4Tests {
    @Test func parsesEveryAACFrameOfASegment() async throws {
        let fixture = try await HLSAudioFixture.make(seconds: 6)
        let fragments = try fixture.segments.map(FragmentedMP4.parseAudioSegment)
        #expect(fragments.count >= 2)
        #expect(fragments.allSatisfy { !$0.packets.isEmpty })
        for (previous, next) in zip(fragments, fragments.dropFirst()) {
            #expect(next.baseDecodeTime == previous.baseDecodeTime + UInt64(previous.packets.count) * 1024)
        }
    }

    @Test func rebuiltSegmentParsesBackIdentically() async throws {
        let fragment = try FragmentedMP4.parseAudioSegment(try await HLSAudioFixture.make(seconds: 2).segments[0])
        let rebuilt = FragmentedMP4.buildAudioSegment(sequence: 7, fragment: fragment)
        #expect(try FragmentedMP4.parseAudioSegment(rebuilt) == fragment)
    }

    @Test func parsesSeveralMovieFragmentsAndPerSampleFields() throws {
        // Hand-built: moof+mdat twice; first trun has per-sample duration+size (flags 0x301), second uses tfhd defaults.
        let segment = HandBuilt.segment(fragments: [
            .init(baseTime: 4096, sizes: [3, 5], perSampleDurations: true),
            .init(baseTime: 6144, sizes: [4], perSampleDurations: false)
        ])
        let parsed = try FragmentedMP4.parseAudioSegment(segment)
        #expect(parsed.baseDecodeTime == 4096 && parsed.trackID == 1)
        #expect(parsed.packets.map(\.count) == [3, 5, 4])
    }

    @Test func rejectsFramesThatAreNot1024Samples() {
        let heAAC = HandBuilt.segment(fragments: [.init(baseTime: 0, sizes: [3, 5], perSampleDurations: true, duration: 2048)])
        #expect(throws: FragmentedMP4.Failure.unsupported) { try FragmentedMP4.parseAudioSegment(heAAC) }
    }

    @Test func surroundInitDeclaresSixChannels() async throws {
        let fixture = try await HLSAudioFixture.make(seconds: 2)
        let patched = try FragmentedMP4.surroundInitSegment(from: fixture.initSegment)
        #expect(patched.count == fixture.initSegment.count)
        #expect(try HandBuilt.channelCount(ofInit: patched) == 6)
        #expect(try HandBuilt.channelConfiguration(ofInit: patched) == 6)
    }

    @Test func rejectsWhatItCannotUpmix() async throws {
        let mono = try await HLSAudioFixture.make(seconds: 2, channels: 1)
        #expect(throws: FragmentedMP4.Failure.unsupported) { try FragmentedMP4.surroundInitSegment(from: mono.initSegment) }
        let slow = try await HLSAudioFixture.make(seconds: 2, sampleRate: 44_100)
        #expect(throws: FragmentedMP4.Failure.unsupported) { try FragmentedMP4.surroundInitSegment(from: slow.initSegment) }
        let good = try await HLSAudioFixture.make(seconds: 2).initSegment
        #expect(throws: FragmentedMP4.Failure.unsupported) {
            try FragmentedMP4.surroundInitSegment(from: HandBuilt.replacingFourCC("mp4a", with: "enca", in: good))
        }
        #expect(throws: FragmentedMP4.Failure.unsupported) {
            try FragmentedMP4.surroundInitSegment(from: HandBuilt.replacingFourCC("mp4a", with: "ec-3", in: good))
        }
        #expect(throws: FragmentedMP4.Failure.malformed) { try FragmentedMP4.parseAudioSegment(Data([0, 0, 0, 8, 0x6D, 0x6F])) }
        #expect(throws: FragmentedMP4.Failure.malformed) { try FragmentedMP4.surroundInitSegment(from: Data(repeating: 0, count: 64)) }
    }
}
```

`HandBuilt` is a private helper enum in the test file, built on `MP4Bytes`: `segment(fragments:)` (with `struct Spec { var baseTime: UInt64; var sizes: [Int]; var perSampleDurations: Bool; var duration: UInt32 = 1024 }`), `channelCount(ofInit:)`, `channelConfiguration(ofInit:)`, `replacingFourCC(_:with:in:)`.

- [ ] **Step 3: Run to verify failure** — `KIT_TEST FragmentedMP4Tests`. Expected: build failure, `FragmentedMP4` not defined.

- [ ] **Step 4: Implement `SurroundFormat` and `FragmentedMP4`**

Decisions the tests do not fix:
- Walk boxes properly (32-bit size, 64-bit size when size is 1, to-end when 0). Never index past the data: any truncation is `.malformed`.
- `parseAudioSegment`: several `moof`/`mdat` pairs and several `trun` per `traf`. Read `tfhd` (track ID, default sample duration and size), `tfdt` (versions 0 and 1), `trun` (optional per-sample duration, size, flags, composition offset). Locate sample data from the `trun` data offset relative to the `moof` start, or from `tfhd` base-data-offset when present. `baseDecodeTime` is the first `tfdt`. No samples is `.malformed`. Any sample whose duration (per-sample, else `tfhd` default) is not 1024 is `.unsupported`; a segment with neither is `.unsupported`.
- `buildAudioSegment`: `moof`(`mfhd`, `traf`(`tfhd` flags `0x020028` with default sample duration 1024 and default sample flags `0x02000000`, `tfdt` version 1, `trun` flags `0x000201` with data offset and per-sample sizes)) + `mdat`.
- `surroundInitSegment`: find the sample entry by walking `moov/trak/mdia/minf/stbl/stsd`, not by byte search. Require `mdhd` timescale 48 000, an `mp4a` entry (anything else, including `enca`, `ac-3`, `ec-3`, is `.unsupported`) with channel count 2 and sample rate 48 000, and in `esds` an AudioSpecificConfig with object type 2 and channel configuration 2. Patch the sample-entry channel count and the AudioSpecificConfig channel configuration to 6 in place; nothing else changes (*measured*: this alone reads back as a valid 5.1 track).

- [ ] **Step 5: Run to verify pass** — `KIT_TEST FragmentedMP4Tests`, then `LINT`.

- [ ] **Step 6: Commit** — `feat(core): fMP4 audio parsing, rebuilding and 5.1 init segment`

---

### Task 2: Surround playlist authoring

**Files:**
- Create: `Packages/OroroKit/Sources/OroroCore/Playback/SurroundPlaylistBuilder.swift`
- Test: `Packages/OroroKit/Tests/OroroCoreTests/SurroundPlaylistBuilderTests.swift`

**Interfaces:**
- Consumes: `SurroundFormat.addedBitsPerSecond`.
- Produces `public enum SurroundPlaylistBuilder`:
  - `struct Multivariant: Equatable, Sendable { public var text: String; public var sources: [URL] }` — `sources[r]` is the original media playlist URL chosen for rendition `r`.
  - `static func multivariant(absolutised: String, localBase: URL) -> Multivariant?` — input is the output of `SubtitlePlaylistBuilder.master` (all URIs already absolute).
  - `struct MediaPlaylist: Equatable, Sendable { public var text: String; public var initURL: URL; public var segments: [URL] }`
  - `static func mediaPlaylist(original: String, originalURL: URL, localBase: URL, rendition: Int) -> MediaPlaylist?` — `originalURL` is the URL **after redirects**.
  - Local layout under `localBase` (ends in `/`): `audio/<r>.m3u8`, `audio/<r>/init.mp4`, `audio/<r>/<n>.m4s`.
  - `enum Resource: Equatable, Sendable { case playlist(rendition: Int), initSegment(rendition: Int), segment(rendition: Int, index: Int) }`, `static func resource(forPath path: String) -> Resource?`.

Rendition rule: one rendition per distinct (`LANGUAGE`, `NAME`) pair across all audio entries. Its source is the entry with that pair in the audio group of the highest-`BANDWIDTH` variant (first such entry in file order if that group lacks the pair). Every audio entry with that pair, in every group, gets the same local URI.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct SurroundPlaylistBuilderTests {
    private static let base = URL(string: "http://127.0.0.1:5000/token/")!
    private static let episode = """
    #EXTM3U
    #EXT-X-VERSION:6
    #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",LANGUAGE="en",AUTOSELECT=YES,DEFAULT=YES,URI="ororo-subs://subtitles/en.m3u8"
    #EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=853x480,AUDIO="aud1",SUBTITLES="subs"
    https://cdn.example.invalid/v/480.m3u8?wmsAuthSign=PLACEHOLDER
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud1",LANGUAGE="eng",NAME="English",URI="https://cdn.example.invalid/a/1.m3u8?wmsAuthSign=PLACEHOLDER"
    #EXT-X-STREAM-INF:BANDWIDTH=400000,AVERAGE-BANDWIDTH=350000,RESOLUTION=426x240,AUDIO="aud2",SUBTITLES="subs"
    https://cdn.example.invalid/v/240.m3u8?wmsAuthSign=PLACEHOLDER
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud2",LANGUAGE="eng",NAME="English",CHANNELS="2",URI="https://cdn.example.invalid/a/2.m3u8?wmsAuthSign=PLACEHOLDER"
    """
    private static let localURI = #"URI="http://127.0.0.1:5000/token/audio/0.m3u8""#

    @Test func pointsEveryAudioGroupAtOneRenditionFromTheBestVariant() throws {
        let result = try #require(SurroundPlaylistBuilder.multivariant(absolutised: Self.episode, localBase: Self.base))
        let lines = result.text.components(separatedBy: "\n")
        #expect(result.sources.count == 1)
        #expect(result.sources[0].path == "/a/1.m3u8" && result.sources[0].query == "wmsAuthSign=PLACEHOLDER")
        let audio = lines.filter { $0.contains("TYPE=AUDIO") }
        #expect(audio.count == 2)
        #expect(audio.allSatisfy { $0.contains(#"CHANNELS="6""#) && !$0.contains(#"CHANNELS="2""#) && $0.contains(Self.localURI) })
        #expect(lines.contains { $0.hasPrefix("#EXT-X-STREAM-INF:BANDWIDTH=1884000,") })
        #expect(lines.contains { $0.hasPrefix("#EXT-X-STREAM-INF:BANDWIDTH=784000,AVERAGE-BANDWIDTH=734000,") })
        #expect(lines.contains("https://cdn.example.invalid/v/480.m3u8?wmsAuthSign=PLACEHOLDER"))
        #expect(lines.contains { $0.contains("TYPE=SUBTITLES") && $0.contains("ororo-subs://subtitles/en.m3u8") })
        #expect(!result.text.contains("/a/1.m3u8") && !result.text.contains("/a/2.m3u8"))
    }

    @Test func keepsDifferentLanguagesAsSeparateRenditions() throws {
        let twoLanguages = Self.episode.replacingOccurrences(
            of: #"GROUP-ID="aud2",LANGUAGE="eng",NAME="English""#, with: #"GROUP-ID="aud1",LANGUAGE="rus",NAME="Russian""#)
        let result = try #require(SurroundPlaylistBuilder.multivariant(absolutised: twoLanguages, localBase: Self.base))
        #expect(result.sources.map(\.path) == ["/a/1.m3u8", "/a/2.m3u8"])
        #expect(result.text.contains("audio/0.m3u8") && result.text.contains("audio/1.m3u8"))
    }

    @Test func declinesWhenAudioIsNotASeparateStereoRendition() {
        let muxed = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nhttps://cdn.example.invalid/v.m3u8\n"
        #expect(SurroundPlaylistBuilder.multivariant(absolutised: muxed, localBase: Self.base) == nil)
        let noURI = "#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"a\",NAME=\"x\"\n"
            + "#EXT-X-STREAM-INF:BANDWIDTH=1000,AUDIO=\"a\"\nhttps://x.invalid/v.m3u8\n"
        #expect(SurroundPlaylistBuilder.multivariant(absolutised: noURI, localBase: Self.base) == nil)
        let surround = Self.episode.replacingOccurrences(of: #"CHANNELS="2""#, with: #"CHANNELS="6""#)
        #expect(SurroundPlaylistBuilder.multivariant(absolutised: surround, localBase: Self.base) == nil)
    }

    private static let media = """
    #EXTM3U
    #EXT-X-VERSION:7
    #EXT-X-TARGETDURATION:5
    #EXT-X-PLAYLIST-TYPE:VOD
    #EXT-X-MAP:URI="init.fmp4?wmsAuthSign=PLACEHOLDER"
    #EXTINF:4.01,
    seg-1.fmp4?wmsAuthSign=PLACEHOLDER
    #EXTINF:3.541,
    seg-2.fmp4?wmsAuthSign=PLACEHOLDER
    #EXT-X-ENDLIST
    """
    private static let mediaURL = URL(string: "https://edge7.example.invalid/a/1.m3u8?wmsAuthSign=PLACEHOLDER")!

    @Test func rewritesTheMediaPlaylistToLocalURLsAndKeepsTheSignedQuery() throws {
        let result = try #require(SurroundPlaylistBuilder.mediaPlaylist(
            original: Self.media, originalURL: Self.mediaURL, localBase: Self.base, rendition: 1))
        #expect(result.initURL.absoluteString == "https://edge7.example.invalid/a/init.fmp4?wmsAuthSign=PLACEHOLDER")
        #expect(result.segments.map(\.absoluteString) == [
            "https://edge7.example.invalid/a/seg-1.fmp4?wmsAuthSign=PLACEHOLDER",
            "https://edge7.example.invalid/a/seg-2.fmp4?wmsAuthSign=PLACEHOLDER"
        ])
        let lines = result.text.components(separatedBy: "\n")
        #expect(lines.contains(#"#EXT-X-MAP:URI="http://127.0.0.1:5000/token/audio/1/init.mp4""#))
        #expect(lines.contains("http://127.0.0.1:5000/token/audio/1/0.m4s"))
        #expect(lines.contains("http://127.0.0.1:5000/token/audio/1/1.m4s"))
        #expect(lines.contains("#EXTINF:3.541,") && lines.contains("#EXT-X-ENDLIST"))
        #expect(!result.text.contains("wmsAuthSign") && !result.text.contains("example.invalid"))
    }

    @Test(arguments: [
        ("#EXT-X-KEY:METHOD=AES-128,URI=\"https://x.invalid/key\"", "#EXTINF:4,"),
        ("#EXT-X-BYTERANGE:1000@0", "#EXTINF:4,"),
        ("#EXT-X-DISCONTINUITY", "#EXTINF:4,"),
        ("#EXT-X-MAP:URI=\"other.mp4\"", "#EXTINF:4,"),
        ("#EXT-X-MAP:URI=\"init.fmp4\",BYTERANGE=\"700@0\"", "#EXT-X-MAP:URI=\"init.fmp4?wmsAuthSign=PLACEHOLDER\"")
    ])
    func declinesMediaPlaylistsItCannotServe(tag: String, replacing: String) {
        let range = Self.media.range(of: replacing)!
        let text = replacing.hasPrefix("#EXTINF") ? Self.media.replacingCharacters(in: range, with: tag + "\n" + replacing)
            : Self.media.replacingCharacters(in: range, with: tag)
        #expect(SurroundPlaylistBuilder.mediaPlaylist(original: text, originalURL: Self.mediaURL, localBase: Self.base, rendition: 0) == nil)
    }

    @Test func declinesLivePlaylistsAndPlaylistsWithoutAnInitSegment() {
        let live = Self.media.replacingOccurrences(of: "#EXT-X-ENDLIST", with: "")
        #expect(SurroundPlaylistBuilder.mediaPlaylist(original: live, originalURL: Self.mediaURL, localBase: Self.base, rendition: 0) == nil)
        let transportStream = "#EXTM3U\n#EXTINF:4,\nseg.ts\n#EXT-X-ENDLIST\n"
        #expect(SurroundPlaylistBuilder.mediaPlaylist(
            original: transportStream, originalURL: Self.mediaURL, localBase: Self.base, rendition: 0) == nil)
    }

    @Test func acceptsAnExplicitNoEncryptionKey() {
        let text = Self.media.replacingOccurrences(of: "#EXT-X-PLAYLIST-TYPE:VOD", with: "#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-KEY:METHOD=NONE")
        #expect(SurroundPlaylistBuilder.mediaPlaylist(original: text, originalURL: Self.mediaURL, localBase: Self.base, rendition: 0) != nil)
    }

    @Test func mapsLocalPathsBackToResources() {
        #expect(SurroundPlaylistBuilder.resource(forPath: "audio/2.m3u8") == .playlist(rendition: 2))
        #expect(SurroundPlaylistBuilder.resource(forPath: "audio/2/init.mp4") == .initSegment(rendition: 2))
        #expect(SurroundPlaylistBuilder.resource(forPath: "audio/2/17.m4s") == .segment(rendition: 2, index: 17))
        #expect(SurroundPlaylistBuilder.resource(forPath: "audio/x.m3u8") == nil)
        #expect(SurroundPlaylistBuilder.resource(forPath: "audio/2/-1.m4s") == nil)
        #expect(SurroundPlaylistBuilder.resource(forPath: "../secret") == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure** — `KIT_TEST SurroundPlaylistBuilderTests`.

- [ ] **Step 3: Implement.** Handle CRLF like `SubtitlePlaylistBuilder`. Multivariant declines (nil): no `TYPE=AUDIO` entry with a URI; any audio entry declaring `CHANNELS` other than `"1"` or `"2"`. Media playlist declines: no `EXT-X-MAP`, more than one `EXT-X-MAP`, a `BYTERANGE` attribute on it, `EXT-X-KEY` with a method other than `NONE`, `EXT-X-BYTERANGE`, `EXT-X-DISCONTINUITY`, no `EXT-X-ENDLIST`, no segments.

- [ ] **Step 4: Run to verify pass** — `KIT_TEST SurroundPlaylistBuilderTests`, `LINT`.

- [ ] **Step 5: Commit** — `feat(core): author surround audio playlists`

---

### Task 3: Upmix interface, placeholder matrix and debug signals

**Files:**
- Create: `Packages/OroroKit/Sources/OroroCore/Playback/SurroundUpmixer.swift`
- Create: `Packages/OroroKit/Sources/OroroCore/Playback/SurroundDebugSignal.swift`
- Test: `Packages/OroroKit/Tests/OroroCoreTests/SurroundUpmixerTests.swift`, `SurroundDebugSignalTests.swift`

**Interfaces:**
- Produces:
  - `public struct SurroundFrames: Equatable, Sendable { public var center, left, right, leftSurround, rightSurround, lfe: [Float] }`, `public init(silence count: Int)`, `var channels: [[Float]]` (C L R Ls Rs LFE), `var count: Int`.
  - `public struct SurroundUpmixer: Sendable { public init(sampleRate: Double = SurroundFormat.sampleRate); public mutating func process(left: [Float], right: [Float]) -> SurroundFrames }` — streaming: state carries between calls, output length equals input length, and the result must not depend on how the input is chunked (process sample by sample).
  - `public enum SurroundDebugSignal: String, Sendable, CaseIterable { case speakerTest, steadyTone; public func frames(startFrame: Int, count: Int) -> SurroundFrames }` — a pure function of the absolute frame index, so it is continuous across segments. `startFrame` may be negative (the transcoder's pre-roll before the start of a title); frames below 0 are silence.
    - `speakerTest`: a 12 s cycle of six 2 s slots in channel order C, L, R, Ls, Rs, LFE. In slot *k* (0-based) only channel *k* sounds: *k* + 1 beeps, each 150 ms on and 150 ms off from the slot start, 1 kHz at amplitude 0.25 (60 Hz for the LFE slot), with 5 ms linear fades on each beep edge.
    - `steadyTone`: 440 Hz at 0.25 in left and right, all other channels silent.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct SurroundUpmixerTests {
    static func sine(_ hz: Double, count: Int = 48_000, amplitude: Float = 0.5) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * .pi * hz * Double($0) / 48_000)) }
    }
    static func rms(_ x: ArraySlice<Float>) -> Float { (x.reduce(0) { $0 + $1 * $1 } / Float(max(x.count, 1))).squareRoot() }

    @Test func outputLengthMatchesInputAcrossChunks() {
        var upmixer = SurroundUpmixer()
        for size in [1, 7, 1024, 5000] {
            let frames = upmixer.process(left: Self.sine(440, count: size), right: Self.sine(550, count: size))
            #expect(frames.channels.allSatisfy { $0.count == size })
        }
    }

    @Test func chunkingDoesNotChangeTheResult() {
        let left = Self.sine(440), right = Self.sine(660)
        var whole = SurroundUpmixer(), pieces = SurroundUpmixer()
        let expected = whole.process(left: left, right: right)
        var joined = [[Float]](repeating: [], count: 6)
        for start in stride(from: 0, to: left.count, by: 1000) {
            let end = min(start + 1000, left.count)
            let part = pieces.process(left: Array(left[start..<end]), right: Array(right[start..<end]))
            for channel in 0..<6 { joined[channel] += part.channels[channel] }
        }
        #expect(joined == expected.channels)
    }

    @Test func monoContentGoesToTheCentreNotTheSurrounds() {
        var upmixer = SurroundUpmixer()
        let voice = Self.sine(1000)
        let frames = upmixer.process(left: voice, right: voice)
        #expect(Self.rms(frames.center[24_000...]) > 0.1)
        #expect(Self.rms(frames.leftSurround[24_000...]) < 0.01 && Self.rms(frames.rightSurround[24_000...]) < 0.01)
    }

    @Test func outOfPhaseContentReachesBothSurrounds() {
        var upmixer = SurroundUpmixer()
        let wide = Self.sine(1000)
        let frames = upmixer.process(left: wide, right: wide.map { -$0 })
        #expect(Self.rms(frames.leftSurround[24_000...]) > 0.05 && Self.rms(frames.rightSurround[24_000...]) > 0.05)
        #expect(Self.rms(frames.center[24_000...]) < 0.01)
    }

    @Test func subwooferChannelIsQuietBassOnly() {
        var bass = SurroundUpmixer(), treble = SurroundUpmixer()
        let low = bass.process(left: Self.sine(50), right: Self.sine(50))
        let high = treble.process(left: Self.sine(2000), right: Self.sine(2000))
        #expect(Self.rms(low.lfe[24_000...]) > 10 * Self.rms(high.lfe[24_000...]))
        // −20 dB: the receiver's bass management, not this channel, feeds the subwoofer.
        #expect(Self.rms(low.lfe[24_000...]) < 0.15 * Self.rms(Self.sine(50)[24_000...]))
        #expect(Self.rms(low.lfe[24_000...]) > 0.02 * Self.rms(Self.sine(50)[24_000...]))
    }
}

@Suite struct SurroundDebugSignalTests {
    private static func rms(_ x: [Float], _ range: Range<Int>) -> Float {
        (x[range].reduce(0) { $0 + $1 * $1 } / Float(range.count)).squareRoot()
    }

    @Test(arguments: 0..<6)
    func speakerTestSoundsOneChannelPerSlot(slot: Int) {
        let frames = SurroundDebugSignal.speakerTest.frames(startFrame: 0, count: 12 * 48_000)
        let firstBeep = slot * 96_000 + 960..<slot * 96_000 + 6_240 // 20–130 ms into the slot
        for channel in 0..<6 {
            let level = Self.rms(frames.channels[channel], firstBeep)
            #expect(channel == slot ? level > 0.1 : level == 0)
        }
    }

    @Test func speakerTestBeepCountIdentifiesTheChannel() {
        // Slot 3 (rear left) has 4 beeps: sound in the 4th beep window (900–1050 ms), silence where a 5th would be (1200–1350 ms).
        let frames = SurroundDebugSignal.speakerTest.frames(startFrame: 3 * 96_000, count: 96_000)
        #expect(Self.rms(frames.leftSurround, 44_160..<49_440) > 0.1)
        #expect(Self.rms(frames.leftSurround, 58_560..<63_840) == 0)
    }

    @Test(arguments: SurroundDebugSignal.allCases)
    func signalIsAFunctionOfTheAbsoluteFrame(signal: SurroundDebugSignal) {
        let whole = signal.frames(startFrame: 5_000, count: 4_096)
        let first = signal.frames(startFrame: 5_000, count: 1_000), second = signal.frames(startFrame: 6_000, count: 3_096)
        for channel in 0..<6 { #expect(first.channels[channel] + second.channels[channel] == whole.channels[channel]) }
    }

    @Test func steadyToneIsContinuousInTheFrontsOnly() {
        let frames = SurroundDebugSignal.steadyTone.frames(startFrame: 0, count: 48_000)
        #expect(Self.rms(frames.left, 0..<48_000) > 0.15 && frames.left == frames.right)
        #expect(frames.center.allSatisfy { $0 == 0 } && frames.leftSurround.allSatisfy { $0 == 0 } && frames.lfe.allSatisfy { $0 == 0 })
    }
}
```

- [ ] **Step 2: Run to verify failure** — `KIT_TEST SurroundUpmixerTests`, `KIT_TEST SurroundDebugSignalTests`.

- [ ] **Step 3: Implement.** Placeholder matrix: `mid = 0.5(L+R)`, `side = 0.5(L−R)`; `C = mid`, `L = left`, `R = right`, `Ls = side`, `Rs = −side`, `LFE = SurroundFormat.lfeGain ×` one-pole low-pass of `mid` at 120 Hz. Deliberately crude: Task 10 replaces the body, not the interface.

- [ ] **Step 4: Run to verify pass** — both suites, `LINT`.

- [ ] **Step 5: Commit** — `feat(core): surround upmixer interface, placeholder matrix and debug signals`

---

### Task 4: Stereo AAC → 5.1 AAC transcoder with seamless joins

**Files:**
- Create: `Packages/OroroUI/Sources/OroroFeatures/Player/SurroundTranscoder.swift`
- Create: `Packages/OroroUI/Tests/OroroFeaturesTests/SurroundProbe.swift`
- Test: `Packages/OroroUI/Tests/OroroFeaturesTests/SurroundTranscoderTests.swift`

**Interfaces:**
- Consumes: `SurroundUpmixer`, `SurroundDebugSignal`, `SurroundFrames`, `SurroundFormat`, `FragmentedMP4`, `HLSAudioFixture`.
- Produces:
  - `struct SurroundTranscoder: Sendable { enum Failure: Error, Equatable { case decoderUnavailable, encoderUnavailable, decodeFailed, encodeFailed }; init(signal: SurroundDebugSignal? = nil); func transcode(previous: [Data], current: [Data], next: [Data], startFrame: Int) throws -> [Data] }`
  - `transcode` returns **exactly `current.count`** raw 5.1 AAC-LC packets, time-aligned with `current` (constant `outputLagFrames` lag). `previous` / `next` are whatever neighbouring packets the caller has (0 to `prerollPackets` / `postrollPackets`; more is truncated). `startFrame` is the absolute frame index of `current`'s first packet (its `baseDecodeTime`); it only matters when `signal` is set, in which case the upmix output is replaced by `signal.frames`. Empty `current` returns `[]`.
  - Test helper `enum SurroundProbe` (shared by Tasks 4 and 6):
    - `static func decode(packets: [Data], channels: Int) throws -> [[Float]]` — `AVAudioConverter` decode of raw AAC packets (2 → stereo, 6 → `MPEG_5_1_D`); returns one array per channel of exactly `packets.count × 1024` frames. No priming is removed.
    - `static func readContainer(initSegment: Data, segments: [Data]) async throws -> [[Float]]` — writes init + segments to a temporary `.mp4` and reads it with `AVURLAsset` + `AVAssetReader`, requesting 6-channel float PCM with layout `kAudioChannelLayoutTag_MPEG_5_1_D` explicitly. Note: the reader silently trims 2112 priming frames (*measured*), so its output starts 2112 frames into the packet stream.
    - `static func bestLag(of signal: [Float], against reference: [Float], maxLag: Int) -> Int` — lag in frames (positive = `signal` late) with the highest cross-correlation.
    - `static func packetErrors(_ a: [Float], _ b: [Float]) -> [Float]` — RMS of `a − b` per 1024-frame block, over the shorter length.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct SurroundTranscoderTests {
    private struct Pieces { var fixture: HLSAudioFixture; var fragments: [FragmentedMP4.AudioFragment]; var output: [[Data]] }

    /// Transcodes each segment on its own, with the neighbours the source would pass.
    private static func transcodeBySegment(seconds: Double, signal: SurroundDebugSignal? = nil) async throws -> Pieces {
        let fixture = try await HLSAudioFixture.make(seconds: seconds)
        let fragments = try fixture.segments.map(FragmentedMP4.parseAudioSegment)
        let transcoder = SurroundTranscoder(signal: signal)
        let output = try fragments.indices.map { index in
            try transcoder.transcode(
                previous: index > 0 ? Array(fragments[index - 1].packets.suffix(SurroundFormat.prerollPackets)) : [],
                current: fragments[index].packets,
                next: index + 1 < fragments.count ? Array(fragments[index + 1].packets.prefix(SurroundFormat.postrollPackets)) : [],
                startFrame: Int(fragments[index].baseDecodeTime))
        }
        return Pieces(fixture: fixture, fragments: fragments, output: output)
    }

    @Test func producesOnePacketPerInputPacket() async throws {
        let pieces = try await Self.transcodeBySegment(seconds: 8)
        #expect(pieces.fragments.count >= 3)
        #expect(pieces.output.map(\.count) == pieces.fragments.map(\.packets.count))
    }

    @Test func joinsAreNoWorseThanTheRestOfTheStream() async throws {
        let pieces = try await Self.transcodeBySegment(seconds: 8)
        let source = pieces.fragments.flatMap(\.packets)
        let stereo = try SurroundProbe.decode(packets: source, channels: 2)
        var upmixer = SurroundUpmixer()
        let truth = upmixer.process(left: stereo[0], right: stereo[1])
        let decoded = try SurroundProbe.decode(packets: pieces.output.flatMap { $0 }, channels: 6)
        let lag = SurroundFormat.outputLagFrames

        var boundaries: Set<Int> = [], block = 0
        for fragment in pieces.fragments.dropLast() {
            block += fragment.packets.count
            boundaries.formUnion(block - 2...block + 2)
        }
        for channel in [1, 3] { // left front, left surround
            let errors = SurroundProbe.packetErrors(Array(decoded[channel].dropFirst(lag)), truth.channels[channel])
            let interior = errors.indices.filter { $0 >= 3 && $0 < errors.count - 2 }
            let nearJoins = interior.filter(boundaries.contains).map { errors[$0] }.max() ?? 0
            let elsewhere = interior.filter { !boundaries.contains($0) }.map { errors[$0] }.max() ?? 0
            // Measured during review: correct scheme ≈ 0.004–0.006 near joins vs 0.004–0.007 elsewhere; a missing post-roll ≈ 0.15.
            #expect(nearJoins <= 1.25 * elsewhere)
            #expect(elsewhere < 0.02)
        }
    }

    @Test func outputLagsTheSourceByExactlyTheEncoderRemainder() async throws {
        let pieces = try await Self.transcodeBySegment(seconds: 4)
        let stereo = try SurroundProbe.decode(packets: pieces.fragments.flatMap(\.packets), channels: 2)
        let decoded = try SurroundProbe.decode(packets: pieces.output.flatMap { $0 }, channels: 6)
        let lag = SurroundProbe.bestLag(of: decoded[1], against: stereo[0], maxLag: 4800)
        #expect((0...128).contains(lag)) // 64 expected; an off-by-one packet would be ±1024 or more
    }

    @Test func everyChannelKeepsItsPlaceThroughEncodingAndTheContainer() async throws {
        let pieces = try await Self.transcodeBySegment(seconds: 13, signal: .speakerTest)
        let initSegment = try FragmentedMP4.surroundInitSegment(from: pieces.fixture.initSegment)
        let segments = zip(pieces.fragments, pieces.output).enumerated().map { index, pair in
            var fragment = pair.0
            fragment.packets = pair.1
            return FragmentedMP4.buildAudioSegment(sequence: UInt32(index + 1), fragment: fragment)
        }
        let channels = try await SurroundProbe.readContainer(initSegment: initSegment, segments: segments)
        #expect(channels.count == 6)
        for slot in 0..<6 {
            // 30–90 ms into the slot's first beep, in reader time (2112-frame trim, 64-frame lag: the beep spans −43…107 ms).
            let window = slot * 96_000 + 1_440..<slot * 96_000 + 4_320
            for channel in 0..<6 {
                let level = (channels[channel][window].reduce(0) { $0 + $1 * $1 } / Float(window.count)).squareRoot()
                #expect(channel == slot ? level > 0.05 : level < 0.01)
            }
        }
    }

    @Test func shortSegmentsAndShortNeighboursKeepTheirPacketCount() async throws {
        let packets = try FragmentedMP4.parseAudioSegment(try await HLSAudioFixture.make(seconds: 2).segments[0]).packets
        let transcoder = SurroundTranscoder()
        #expect(try transcoder.transcode(previous: [], current: [packets[0]], next: [], startFrame: 0).count == 1)
        #expect(try transcoder.transcode(
            previous: Array(packets[0..<2]), current: Array(packets[2..<4]), next: [packets[4]], startFrame: 2048).count == 2)
        #expect(try transcoder.transcode(
            previous: Array(packets[0..<4]), current: Array(packets[4..<7]), next: [], startFrame: 4096).count == 3)
        #expect(try transcoder.transcode(previous: [], current: [], next: [], startFrame: 0).isEmpty)
    }

    @Test func garbageInputDoesNotCrash() {
        let garbage = [Data(repeating: 0xAB, count: 300)]
        // The decoder may reject it or conceal it; either way the call returns.
        let result = Result { try SurroundTranscoder().transcode(previous: [], current: garbage, next: [], startFrame: 0) }
        if case .success(let packets) = result { #expect(packets.count == 1) }
    }
}
```

- [ ] **Step 2: Run to verify failure** — `UI_TEST SurroundTranscoderTests`.

- [ ] **Step 3: Implement `SurroundTranscoder`**

Fresh `AVAudioConverter` instances per call: stereo AAC (`kAudioFormatMPEG4AAC`, 48 kHz, 1024 frames per packet) → float PCM; 6-channel float PCM with layout `kAudioChannelLayoutTag_MPEG_5_1_D` → AAC at `SurroundFormat.bitRate`. Feed the whole input buffer once, then signal end-of-stream to flush the encoder.

Alignment (all *measured* during review; do not re-derive, do pin with the tests above):

```
P = prerollPackets (4), Q = postrollPackets (2), N = current.count
1. Decode  previous.suffix(P) + current + next.prefix(Q)  with one decoder.
   The decoder returns exactly 1024 frames per packet, no priming removed.
   Only the first packet's 1024 frames are unreliable: zero them when `previous` is non-empty.
2. Pad the PCM with silence so `current` always starts at frame P·1024 and is followed by Q·1024 frames:
   prepend (P − previous.count)·1024 zero frames, append (Q − next.count)·1024 zero frames.
3. Upmix the whole padded span with a fresh SurroundUpmixer (or take signal.frames(startFrame: startFrame − P·1024, …)).
4. Encode the whole span. Output packet k carries input frames [k·1024 − 2112, k·1024 − 1088).
   Emit packets [P + encoderDelayPackets, P + encoderDelayPackets + N).
   Fewer packets than that is `.encodeFailed`. Never pad by repeating packets.
```

Consequence for the upmixer: nothing in it may depend on audio older than 3 packets (3072 frames, 64 ms).

- [ ] **Step 4: Run to verify pass** — `UI_TEST SurroundTranscoderTests`, `LINT`.

- [ ] **Step 5: Commit** — `feat(player): stereo to 5.1 AAC transcoder with seamless joins`

---

### Task 5: Loopback HTTP server

**Files:**
- Create: `Packages/OroroUI/Sources/OroroFeatures/Player/LoopbackServer.swift`
- Test: `Packages/OroroUI/Tests/OroroFeaturesTests/LoopbackServerTests.swift`

**Interfaces:**
- Produces:
  - `struct LoopbackResponse: Sendable { var status: Int; var contentType: String; var body: Data; static let notFound: LoopbackResponse; static let badGateway: LoopbackResponse }`
  - `final class LoopbackServer: Sendable { init(handler: @escaping @Sendable (_ path: String) async -> LoopbackResponse); func start() async throws -> URL; func ensureListening() async -> Bool; func stop() }`
  - `start()` binds `127.0.0.1` on an ephemeral port and returns `http://127.0.0.1:<port>/<token>/` with a fresh `UUID().uuidString` token. The handler receives the path after the token prefix (no leading slash, query stripped). Requests without the token prefix get 404 without reaching the handler. Only `GET`; anything else is 405.
  - `ensureListening()`: true if the listener is ready; otherwise tries to listen again on **the same port with the same token** and returns whether that worked. False if never started or stopped by `stop()`.
  - When the client closes the connection before the response is ready, the handler's task is cancelled.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct LoopbackServerTests {
    static func get(_ url: URL) async throws -> (status: Int, body: Data) {
        let (data, response) = try await URLSession(configuration: .ephemeral).data(from: url)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
    private static let playlist = LoopbackResponse(status: 200, contentType: "application/vnd.apple.mpegurl", body: Data("#EXTM3U".utf8))

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
        let server = LoopbackServer { _ in
            do { try await Task.sleep(for: .seconds(30)) } catch { cancelled.continuation.yield() }
            return .notFound
        }
        let base = try await server.start()
        defer { server.stop() }
        let request = Task { try await Self.get(base.appending(path: "audio/0/0.m4s")) }
        try await Task.sleep(for: .milliseconds(200))
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
}
```

- [ ] **Step 2: Run to verify failure** — `UI_TEST LoopbackServerTests`.

- [ ] **Step 3: Implement with `NWListener`.** `NWParameters.tcp` with `requiredLocalEndpoint` on `127.0.0.1`. Read until the header terminator, answer with `Content-Length` and `Connection: close`, then close. Malformed or oversized (over 16 KB) request heads close the connection. `stop()` is idempotent. Loopback IP-literal URLs are outside App Transport Security (*verified*), so `URLSession` works in the test runner; if a test nevertheless fails with error −1022, replace the test client with an `NWConnection`.

- [ ] **Step 4: Run to verify pass** — `UI_TEST LoopbackServerTests`, `LINT`.

- [ ] **Step 5: Commit** — `feat(player): loopback HTTP server`

---

### Task 6: Surround audio source

**Files:**
- Create: `Packages/OroroUI/Sources/OroroFeatures/Player/SurroundAudioSource.swift`
- Create: `Packages/OroroUI/Tests/OroroFeaturesTests/FixtureOrigin.swift`
- Test: `Packages/OroroUI/Tests/OroroFeaturesTests/SurroundAudioSourceTests.swift`

**Interfaces:**
- Consumes: `LoopbackServer`, `LoopbackResponse`, `SurroundTranscoder`, `SurroundPlaylistBuilder`, `FragmentedMP4`, `SurroundFormat`, `SubtitleResourceResponder.ResolvingFetch`, `SubtitleResourceLoader.download`.
- Produces:
  - `enum SurroundFailure: Sendable, Equatable { case format, starved, slowDevice }`
  - `protocol SurroundSource: Sendable { func start() async throws -> URL; func author(multivariant: String) async -> String?; func ensureServing() async -> Bool; nonisolated func stop() }`
  - `typealias SurroundTranscode = @Sendable (_ previous: [Data], _ current: [Data], _ next: [Data], _ startFrame: Int) throws -> [Data]`
  - `actor SurroundAudioSource: SurroundSource` with
    `init(fetch: @escaping SubtitleResourceResponder.ResolvingFetch = SubtitleResourceLoader.download, transcode: @escaping SurroundTranscode = SurroundAudioSource.liveTranscode(signal: nil), now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }, onFailure: @escaping @Sendable (SurroundFailure) -> Void)`,
    `static func liveTranscode(signal: SurroundDebugSignal?) -> SurroundTranscode`, and `func respond(to path: String) async -> LoopbackResponse`.

Behaviour:
- `start()` creates a `LoopbackServer` whose handler is `respond(to:)`, starts it and returns its base URL. `stop()` stops the server (synchronous, idempotent). `ensureServing()` forwards to `LoopbackServer.ensureListening()`.
- **`author(multivariant:)` is the pre-flight.** Nil unless `start()` succeeded. Runs `SurroundPlaylistBuilder.multivariant`; for every rendition fetches the media playlist (rewriting it with the **redirected** URL the fetch returns), the init segment (`surroundInitSegment`) and segment 0 (`parseAudioSegment`), and caches all three. If anything is declined, unsupported, malformed or fails to fetch, returns nil (the caller then leaves the playlist untouched). `onFailure` is **not** called for a pre-flight decline.
- `respond`: before a successful `author`, everything is 404. `.playlist(r)` and `.initSegment(r)` serve the cached results. `.segment(r, n)`:
  - fetch (in parallel) and parse segments `n − 1`, `n`, `n + 1` that exist and are not cached; transcode with `previous = suffix(prerollPackets)`, `next = prefix(postrollPackets)`, `startFrame = Int(baseDecodeTime)`; rebuild with the original track ID and base decode time, `sequence = n + 1`.
  - A transport error fetching segment `n` → `.badGateway` (502), no `onFailure`. A transport error fetching only a neighbour → generate without that neighbour.
  - A parse or transcode error → `onFailure(.format)`, 404.
  - Unknown rendition or index out of range → 404, no `onFailure`.
- Caches, memory only: parsed original fragments for the 8 most recently used `(r, n)`; generated segments for the 4 most recent. Concurrent requests for one segment share one generation. At most 2 transcodes run at once (others wait); transcodes run off the actor.
- Health, judged over the last 5 **completed, uncancelled** segment requests, each compared with its own duration `d = packets × 1024 / 48 000` s:
  - `slowDevice`: transcode time alone exceeded `0.5 × d` in at least 3 of them.
  - `starved`: total time from request to response (waiting, fetching, transcoding) exceeded `d` in at least 3 of them.
  - Check `slowDevice` first. Either calls `onFailure` with that case.
- `onFailure` fires at most once per source. A cancelled request (task cancellation) abandons its work where it can and never counts toward health or failure.
- Logging (never a URL): at `.notice`, one line when `author` accepts or declines (with the reason category) and one when `onFailure` fires (with the case); at `.debug`, one line per generated segment: rendition, index, packets, transcode ms, total ms.

- [ ] **Step 1: Write `FixtureOrigin` and the failing tests**

```swift
/// A fake CDN built from `HLSAudioFixture`: one multivariant playlist, one stereo audio rendition.
final class FixtureOrigin: Sendable {
    static let multivariantURL = URL(string: "https://origin.invalid/main.m3u8?wmsAuthSign=PLACEHOLDER")!
    init(fixture: HLSAudioFixture, redirectAudioPlaylistTo host: String? = nil)
    var multivariant: String { get }             // already absolutised; audio group URI → https://origin.invalid/a/audio.m3u8?wmsAuthSign=PLACEHOLDER
    var fetch: SubtitleResourceResponder.ResolvingFetch { get }
    func fetchCount(pathSuffix: String) -> Int   // e.g. "seg-1.mp4"
    func failRequests(pathSuffix: String, _ failing: Bool)  // throws SubtitleResourceLoader.FetchError.transport(code: -1009)
    func replaceInit(with data: Data)
    var segmentCount: Int { get }
}
```

Every request must carry `wmsAuthSign=PLACEHOLDER` in its query, otherwise `fetch` throws `FetchError.http(status: 403)`. Segment URLs in the audio playlist are relative (`seg-0.mp4?wmsAuthSign=PLACEHOLDER`); with `redirectAudioPlaylistTo`, the playlist fetch reports that host as its final URL and segments are only served from that host.

```swift
@Suite struct SurroundAudioSourceTests {
    private final class Failures: Sendable {
        private let values = Mutex<[SurroundFailure]>([])
        var all: [SurroundFailure] { values.withLock { $0 } }
        func record(_ failure: SurroundFailure) { values.withLock { $0.append(failure) } }
    }
    private struct Started { var source: SurroundAudioSource; var base: URL; var authored: String?; var failures: Failures }

    private static func start(_ origin: FixtureOrigin, transcode: SurroundTranscode? = nil,
                              now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }) async throws -> Started {
        let failures = Failures()
        let source = SurroundAudioSource(fetch: origin.fetch, transcode: transcode ?? SurroundAudioSource.liveTranscode(signal: nil),
                                         now: now, onFailure: failures.record)
        let base = try await source.start()
        return Started(source: source, base: base, authored: await source.author(multivariant: origin.multivariant), failures: failures)
    }

    @Test func servesAPlayableSurroundRenditionOverHTTP() async throws {
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 8))
        let started = try await Self.start(origin)
        defer { started.source.stop() }
        let authored = try #require(started.authored)
        #expect(authored.contains("\(started.base.absoluteString)audio/0.m3u8") && authored.contains(#"CHANNELS="6""#))
        let playlist = String(decoding: try await LoopbackServerTests.get(started.base.appending(path: "audio/0.m3u8")).body, as: UTF8.self)
        #expect(!playlist.contains("origin.invalid") && !playlist.contains("wmsAuthSign") && !authored.contains("/a/audio.m3u8"))
        let initSegment = try await LoopbackServerTests.get(started.base.appending(path: "audio/0/init.mp4")).body
        var segments: [Data] = []
        for index in 0..<origin.segmentCount {
            let response = try await LoopbackServerTests.get(started.base.appending(path: "audio/0/\(index).m4s"))
            #expect(response.status == 200)
            segments.append(response.body)
        }
        let channels = try await SurroundProbe.readContainer(initSegment: initSegment, segments: segments)
        #expect(channels.count == 6 && abs(channels[0].count - 8 * 48_000) < 4096)
        #expect(started.failures.all.isEmpty)
    }

    @Test func resolvesSegmentsAgainstTheRedirectedPlaylistURL() async throws {
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 4), redirectAudioPlaylistTo: "edge7.invalid")
        let started = try await Self.start(origin)
        defer { started.source.stop() }
        #expect(started.authored != nil)
        #expect(await started.source.respond(to: "audio/0/1.m4s").status == 200)
    }

    @Test func neighboursAreFetchedOnceAcrossSequentialRequests() async throws {
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 8))
        let started = try await Self.start(origin)
        defer { started.source.stop() }
        for index in 0..<origin.segmentCount { #expect(await started.source.respond(to: "audio/0/\(index).m4s").status == 200) }
        for index in 0..<origin.segmentCount { #expect(origin.fetchCount(pathSuffix: "seg-\(index).mp4") == 1) }
    }

    @Test func concurrentRequestsForOneSegmentTranscodeOnce() async throws {
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 6))
        let calls = Mutex(0)
        let live = SurroundAudioSource.liveTranscode(signal: nil)
        let started = try await Self.start(origin, transcode: { previous, current, next, start in
            calls.withLock { $0 += 1 }
            return try live(previous, current, next, start)
        })
        defer { started.source.stop() }
        let bodies = await withTaskGroup(of: Data.self) { group in
            for _ in 0..<4 { group.addTask { await started.source.respond(to: "audio/0/1.m4s").body } }
            return await group.reduce(into: [Data]()) { $0.append($1) }
        }
        #expect(calls.withLock { $0 } == 1 && Set(bodies).count == 1 && !bodies[0].isEmpty)
    }

    @Test func unknownAndOutOfRangeRequestsAre404WithoutFallback() async throws {
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 4))
        let started = try await Self.start(origin)
        defer { started.source.stop() }
        for path in ["audio/0/999.m4s", "audio/5.m3u8", "audio/5/0.m4s", "bogus"] {
            #expect(await started.source.respond(to: path).status == 404)
        }
        #expect(started.failures.all.isEmpty)
    }

    @Test func nothingIsServedBeforeAuthoring() async throws {
        let failures = Failures()
        let source = SurroundAudioSource(fetch: FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 2)).fetch,
                                         onFailure: failures.record)
        _ = try await source.start()
        defer { source.stop() }
        #expect(await source.respond(to: "audio/0.m3u8").status == 404)
    }

    @Test func transportErrorsAre502WithoutFallbackAndRecover() async throws {
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 8))
        let started = try await Self.start(origin)
        defer { started.source.stop() }
        origin.failRequests(pathSuffix: "seg-2.mp4", true)
        #expect(await started.source.respond(to: "audio/0/2.m4s").status == 502)
        #expect(await started.source.respond(to: "audio/0/1.m4s").status == 200) // only a neighbour is missing
        origin.failRequests(pathSuffix: "seg-2.mp4", false)
        #expect(await started.source.respond(to: "audio/0/2.m4s").status == 200)
        #expect(started.failures.all.isEmpty)
    }

    @Test func preflightDeclinesUnsupportedAudioWithoutFailure() async throws {
        let mono = try await HLSAudioFixture.make(seconds: 2, channels: 1)
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 4))
        origin.replaceInit(with: mono.initSegment)
        let started = try await Self.start(origin)
        defer { started.source.stop() }
        #expect(started.authored == nil && started.failures.all.isEmpty)
    }

    @Test func preflightDeclinesMuxedAudioAndUnreachableOrigins() async throws {
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 4))
        let started = try await Self.start(origin)
        defer { started.source.stop() }
        let muxed = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nhttps://origin.invalid/v.m3u8\n"
        #expect(await started.source.author(multivariant: muxed) == nil)
        origin.failRequests(pathSuffix: "audio.m3u8", true)
        let second = try await Self.start(origin)
        defer { second.source.stop() }
        #expect(second.authored == nil && second.failures.all.isEmpty)
    }

    @Test func aBrokenSegmentReportsAFormatFailureOnce() async throws {
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 8))
        let started = try await Self.start(origin, transcode: { _, _, _, _ in throw SurroundTranscoder.Failure.decodeFailed })
        defer { started.source.stop() }
        #expect(await started.source.respond(to: "audio/0/1.m4s").status == 404)
        #expect(await started.source.respond(to: "audio/0/2.m4s").status == 404)
        #expect(started.failures.all == [.format])
    }

    @Test func aDeviceTooSlowToTranscodeIsReportedAfterThreeSlowSegments() async throws {
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 12))
        let clock = Mutex(ContinuousClock.now)
        let live = SurroundAudioSource.liveTranscode(signal: nil)
        let started = try await Self.start(origin, transcode: { previous, current, next, start in
            clock.withLock { $0 += .seconds(1.5) } // 1.5 s for a ~2 s segment: over half real time
            return try live(previous, current, next, start)
        }, now: { clock.withLock { $0 } })
        defer { started.source.stop() }
        _ = await started.source.respond(to: "audio/0/0.m4s")
        _ = await started.source.respond(to: "audio/0/1.m4s")
        #expect(started.failures.all.isEmpty)
        _ = await started.source.respond(to: "audio/0/2.m4s")
        #expect(started.failures.all == [.slowDevice])
    }

    @Test func slowFetchingIsReportedAsStarvedNotAsASlowDevice() async throws {
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 12))
        let clock = Mutex(ContinuousClock.now)
        let slowFetch: SubtitleResourceResponder.ResolvingFetch = { url in
            if url.path.contains("seg-") { clock.withLock { $0 += .seconds(3) } }
            return try await origin.fetch(url)
        }
        let failures = Failures()
        let source = SurroundAudioSource(fetch: slowFetch, now: { clock.withLock { $0 } }, onFailure: failures.record)
        _ = try await source.start()
        defer { source.stop() }
        #expect(await source.author(multivariant: origin.multivariant) != nil)
        for index in 1...3 { _ = await source.respond(to: "audio/0/\(index).m4s") }
        #expect(failures.all == [.starved])
    }
}
```

- [ ] **Step 2: Run to verify failure** — `UI_TEST SurroundAudioSourceTests`.
- [ ] **Step 3: Implement** as specified under Behaviour.
- [ ] **Step 4: Run to verify pass** — `UI_TEST SurroundAudioSourceTests`, `LINT`.
- [ ] **Step 5: Commit** — `feat(player): surround audio source with pre-flight and health checks`

---

### Task 7: Wire surround into playback

**Files:**
- Create: `Packages/OroroUI/Sources/OroroFeatures/Player/SurroundPolicy.swift`
- Create: `Packages/OroroUI/Tests/OroroFeaturesTests/PlayerTestDoubles.swift`
- Modify: `Packages/OroroUI/Sources/OroroFeatures/Player/SubtitleProvider.swift`
- Modify: `Packages/OroroUI/Sources/OroroFeatures/Player/SubtitleResourceLoader.swift` (`SubtitleResourceResponder` initialisers and `response(for:duration:)`; `SubtitleResourceLoader.init`)
- Modify: `Packages/OroroUI/Sources/OroroFeatures/Player/AVPlayerEngine.swift` (`init`, `load`, `tearDownItem`, `stop`)
- Modify: `Packages/OroroUI/Sources/OroroFeatures/Player/PlayerScreen.swift:83`
- Modify: `Apps/TV/Info.plist`
- Test: `SurroundPolicyTests.swift`, `SubtitleProviderTests.swift` (new), additions to `SubtitleResourceLoaderTests.swift` and `AVPlayerEngineTests.swift`

**Interfaces:**
- Consumes: `SurroundSource`, `SurroundAudioSource`, `SurroundFailure`.
- Produces:
  - `public enum AudioOutput { public static let surroundChannelCount = 6; @MainActor public static func channelCount() -> Int; public static func supportsSurround(channels: Int) -> Bool; @MainActor public static var lastObservedChannelCount: Int? }` — `channelCount()` is `AVAudioSession.sharedInstance().maximumOutputNumberOfChannels`. `lastObservedChannelCount` is set by the engine on every load (memory only).
  - `struct SurroundPolicy: Sendable { var isEnabled: @MainActor @Sendable () async -> Bool; var makeSource: @MainActor @Sendable (_ onFailure: @escaping @Sendable (SurroundFailure) -> Void) -> any SurroundSource; static let disabled: SurroundPolicy; static func live(isEnabled: @escaping @MainActor @Sendable () async -> Bool) -> SurroundPolicy }` — `.live` makes a `SurroundAudioSource`; on iOS `.live` returns `.disabled`.
  - `SubtitleProvider.makeAsset(for:preferredLanguage:surround:)` gains `surround: (any SurroundSource)?`. With a non-nil source the synthetic `ororo-subs` playlist is always used, even for a title without subtitles.
  - `SubtitleResourceResponder` and `SubtitleResourceLoader.init` gain `authorAudio: (@Sendable (String) async -> String?)? = nil`, applied to the multivariant text after `SubtitlePlaylistBuilder.master`; nil result leaves the text unchanged.
  - `AVPlayerEngine.init(subtitles: any SubtitleProvider = HLSInjectedSubtitles(), surround: SurroundPolicy = .disabled, outputChannels: @escaping @MainActor () -> Int = AudioOutput.channelCount, readyTimeout: Duration = AVPlayerEngine.readyTimeout)`.
  - Test doubles (`PlayerTestDoubles.swift`): `TestMedia.silentWAV()` (move the existing private helper out of `AVPlayerEngineTests`), `final class RecordingSubtitles: SubtitleProvider` (records `surround != nil` per `makeAsset` call; returns `AVURLAsset(url:)` of a URL supplied by the test, a silent WAV by default), `final class FakeSurroundSource: SurroundSource` (counts `start`/`stop`, configurable `start` failure and `ensureServing` result, exposes the `onFailure` it was created with).

Surround is used for a load when all hold, checked in this order **after** `AVAudioSession.setActive(true)`: the engine has not disabled it (Task 8), `AudioOutput.supportsSurround(channels: outputChannels())`, `await surround.isEnabled()`, and `source.start()` succeeds. The engine logs one `.notice` line per load: output channels, the route's first output port type, and whether surround is used.

- [ ] **Step 1: Write the failing tests**

```swift
// SurroundPolicyTests
@Suite struct SurroundPolicyTests {
    @Test(arguments: [(2, false), (5, false), (6, true), (8, true)])
    func surroundNeedsSixOutputChannels(channels: Int, expected: Bool) {
        #expect(AudioOutput.supportsSurround(channels: channels) == expected)
    }
    @Test @MainActor func disabledPolicyIsNeverEnabled() async {
        #expect(await SurroundPolicy.disabled.isEnabled() == false)
    }
}

// SubtitleProviderTests
@Suite @MainActor struct SubtitleProviderTests {
    private static let stream = URL(string: "https://example.invalid/hls/stream.m3u8?wmsAuthSign=PLACEHOLDER")!
    private static let bare = Playback(streamURL: stream, subtitles: [], fetchedAt: .now)

    @Test func titleWithoutSubtitlesPlaysTheStreamDirectlyWithoutSurround() {
        #expect(HLSInjectedSubtitles().makeAsset(for: Self.bare, preferredLanguage: nil, surround: nil).url == Self.stream)
    }
    @Test func titleWithoutSubtitlesUsesTheSyntheticPlaylistWithSurround() {
        let asset = HLSInjectedSubtitles().makeAsset(for: Self.bare, preferredLanguage: nil, surround: FakeSurroundSource())
        #expect(asset.url == SubtitlePlaylistBuilder.masterURL())
    }
}

// SubtitleResourceLoaderTests additions
@Test func appliesAudioAuthoringToTheMultivariantPlaylist() async throws {
    let responder = SubtitleResourceResponder(
        playback: Self.playback, preferredLanguage: "en", resolvingFetch: { _ in (Data(Self.original.utf8), Self.streamURL) },
        authorAudio: { $0 + "#AUTHORED\n" })
    let text = String(decoding: try await responder.response(for: SubtitlePlaylistBuilder.masterURL(), duration: 0).data, as: UTF8.self)
    #expect(text.hasSuffix("#AUTHORED\n") && text.contains(#"SUBTITLES="subs""#))
}
@Test func keepsThePlaylistWhenAudioAuthoringDeclines() async throws {
    let fetch: SubtitleResourceResponder.ResolvingFetch = { _ in (Data(Self.original.utf8), Self.streamURL) }
    let plain = SubtitleResourceResponder(playback: Self.playback, preferredLanguage: "en", resolvingFetch: fetch)
    let declined = SubtitleResourceResponder(playback: Self.playback, preferredLanguage: "en", resolvingFetch: fetch, authorAudio: { _ in nil })
    let url = SubtitlePlaylistBuilder.masterURL()
    #expect(try await declined.response(for: url, duration: 0).data == plain.response(for: url, duration: 0).data)
}

// AVPlayerEngineTests additions (@MainActor; every test ends with engine.stop())
private static func engine(_ subtitles: RecordingSubtitles, source: FakeSurroundSource, enabled: Bool = true,
                           channels: Int = 6) -> AVPlayerEngine {
    AVPlayerEngine(subtitles: subtitles,
                   surround: SurroundPolicy(isEnabled: { enabled }, makeSource: { onFailure in source.adopt(onFailure) }),
                   outputChannels: { channels }, readyTimeout: .seconds(5))
}
@Test func loadUsesSurroundWhenEnabledOnASixChannelOutput() async throws {
    let subtitles = RecordingSubtitles(), source = FakeSurroundSource()
    let engine = Self.engine(subtitles, source: source)
    try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
    #expect(subtitles.surroundFlags == [true] && source.startCount == 1)
    #expect(AudioOutput.lastObservedChannelCount == 6)
    engine.stop()
    #expect(source.stopCount == 1)
}
@Test(arguments: [(false, 6), (true, 2)])
func loadSkipsSurroundWhenDisabledOrStereo(enabled: Bool, channels: Int) async throws {
    let subtitles = RecordingSubtitles(), source = FakeSurroundSource()
    let engine = Self.engine(subtitles, source: source, enabled: enabled, channels: channels)
    try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
    #expect(subtitles.surroundFlags == [false] && source.startCount == 0)
    engine.stop()
}
@Test func loadPlaysOriginalAudioWhenTheSourceCannotStart() async throws {
    let subtitles = RecordingSubtitles(), source = FakeSurroundSource(startFails: true)
    let engine = Self.engine(subtitles, source: source)
    try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
    #expect(subtitles.surroundFlags == [false])
    engine.stop()
}
@Test func aSecondLoadStopsTheFirstSource() async throws {
    let subtitles = RecordingSubtitles(), source = FakeSurroundSource()
    let engine = Self.engine(subtitles, source: source)
    try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
    try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
    #expect(source.startCount == 2 && source.stopCount == 1 && subtitles.surroundFlags == [true, true])
    engine.stop()
}
```

`Self.playback` is a `Playback` with one subtitle and an `example.invalid` stream URL.

- [ ] **Step 2: Run to verify failure** — `UI_TEST SurroundPolicyTests`, `SubtitleProviderTests`, `SubtitleResourceLoaderTests`, `AVPlayerEngineTests`.

- [ ] **Step 3: Implement**

- `AVPlayerEngine.load`: `tearDownItem()` stops and drops any current source. After `setActive(true)`: read `outputChannels()`, store it in `AudioOutput.lastObservedChannelCount`, decide as specified, log. `stop()` stops the source too. The `onFailure` closure passed to `makeSource` does nothing yet (Task 8).
- `HLSInjectedSubtitles.makeAsset`: pass `authorAudio: { await source.author(multivariant: $0) }` to the loader when a source is given.
- `PlayerScreen.swift:83`: `AVPlayerEngine(surround: .live(isEnabled: { true }))` (Task 11 swaps the closure for the stored preference).
- `Apps/TV/Info.plist`, inside the top-level `<dict>`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
	<key>NSAllowsLocalNetworking</key>
	<true/>
</dict>
```

- [ ] **Step 4: Run to verify pass** — the four suites, `UI_BUILD_IOS`, `LINT`.
- [ ] **Step 5: Run the full suites** — `swift test --package-path Packages/OroroKit` and the whole `OroroUI-Package` scheme on the tvOS simulator. Expected: all pass.
- [ ] **Step 6: Commit** — `feat(player): play generated 5.1 audio when the output supports it`

---

### Task 8: Fall back to original audio; survive sleep

**Files:**
- Modify: `Packages/OroroUI/Sources/OroroFeatures/Contracts/Playback.swift` (`PlayerEngine`, `PlayerEvent`)
- Modify: `Packages/OroroUI/Sources/OroroFeatures/Player/AVPlayerEngine.swift`
- Modify: `Packages/OroroUI/Sources/OroroFeatures/Player/PlaybackSession.swift` (`handle(_:)`, `streamFailed()`, `sceneBecameActive()`)
- Test: additions to `AVPlayerEngineTests.swift` and `PlaybackSessionTests.swift`

**Interfaces:**
- Produces:
  - `PlayerEvent` gains `case surroundFailed`.
  - `PlayerEngine` gains `func disableSurround()` with a default empty implementation in a protocol extension (so existing fakes compile), and `func sceneBecameActive() async` likewise.
  - `AVPlayerEngine.surroundFailed(_ failure: SurroundFailure, generation: Int)` (internal; the source's `onFailure` hops to the main actor and calls it with the generation captured at load).

Engine behaviour:
- A `generation` counter increments on every `load` and on `stop()`. `surroundFailed` is ignored unless its generation is current, the engine is not stopped and a source is active.
- On an accepted failure: set `surroundDisabled = true` for the rest of this engine's life; if the failure is `.slowDevice`, also set a process-wide flag (`static` on the engine) that disables surround until the app is relaunched. Then:
  - **no load in flight:** yield `.surroundFailed`. Leave the item and the source alone (the session reloads; the next `load` tears them down).
  - **a load is in flight** (between `replaceCurrentItem` and `waitUntilReady` returning): yield nothing. When `waitUntilReady` then throws, `load` checks the flag and, once, rebuilds the asset with `surround: nil`, replaces the item and waits again, continuing the same call with its own `startAt`.
- `disableSurround()` sets `surroundDisabled = true`.
- `sceneBecameActive()`: if a source is active and `await source.ensureServing()` is false, treat it as `surroundFailed(.format, generation: current)`.
- Both disabled flags are checked first in the Task 7 decision.

Session behaviour:
- `handle(.surroundFailed)`: `guard phase == .playing`, then `await reloadStream(automatic: false)` — the normal loading state, a refetch, the current position and the current subtitle preference. It does not touch `autoRecoveryUsed`.
- `streamFailed()`: call `engine.disableSurround()` before its automatic reload, so recovery always retries with original audio. `sceneBecameActive()`'s expired-URL path must **not** disable surround: give `streamFailed` a `keepSurround: Bool = false` parameter and pass `true` there.
- `sceneBecameActive()` also calls `await engine.sceneBecameActive()` first (when not dismissed).

Why both orders are safe: if the item's own `.failed` reaches the session before `.surroundFailed`, `streamFailed` reloads in stereo and the later `.surroundFailed` finds `phase != .playing`; in the other order `.failed` finds `phase != .playing`. One reload either way.

- [ ] **Step 1: Write the failing tests**

```swift
// AVPlayerEngineTests additions
@Test func aFailureDuringPlaybackEmitsSurroundFailedAndDisablesSurround() async throws {
    let subtitles = RecordingSubtitles(), source = FakeSurroundSource()
    let engine = Self.engine(subtitles, source: source)
    var events = engine.events.makeAsyncIterator()
    try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
    source.reportFailure(.format)
    while let event = await events.next(), event != .surroundFailed {}
    try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
    #expect(subtitles.surroundFlags == [true, false] && source.startCount == 1)
    engine.stop()
}
@Test func aFailureWhileLoadingRetriesTheSameLoadWithoutSurround() async throws {
    // The surround asset can never become ready (missing file); the source fails 100 ms into the load.
    let subtitles = RecordingSubtitles(surroundAssetURL: URL(fileURLWithPath: "/nonexistent-\(UUID()).mp4"))
    let source = FakeSurroundSource(failsAfterStart: .milliseconds(100))
    let engine = Self.engine(subtitles, source: source)
    try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil) // returns normally, once
    #expect(subtitles.surroundFlags == [true, false])
    engine.stop()
}
@Test func aFailureFromAnEarlierLoadIsIgnored() async throws {
    let subtitles = RecordingSubtitles(), source = FakeSurroundSource()
    let engine = Self.engine(subtitles, source: source)
    try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
    let stale = source.onFailure
    try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
    stale?(.format)
    try await Task.sleep(for: .milliseconds(100))
    try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
    #expect(subtitles.surroundFlags == [true, true, true])
    engine.stop()
}
@Test func aFailureAfterStopIsIgnored() async throws {
    let subtitles = RecordingSubtitles(), source = FakeSurroundSource()
    let engine = Self.engine(subtitles, source: source)
    try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
    engine.stop()
    source.reportFailure(.format)
    try await Task.sleep(for: .milliseconds(100))
    #expect(engine.player.currentItem == nil)
}
@Test func disableSurroundAppliesToTheNextLoad() async throws {
    let subtitles = RecordingSubtitles(), source = FakeSurroundSource()
    let engine = Self.engine(subtitles, source: source)
    engine.disableSurround()
    try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
    #expect(subtitles.surroundFlags == [false])
    engine.stop()
}
@Test func aDeadServerOnReturnToTheForegroundIsASurroundFailure() async throws {
    let subtitles = RecordingSubtitles(), source = FakeSurroundSource(servesAfterWake: false)
    let engine = Self.engine(subtitles, source: source)
    var events = engine.events.makeAsyncIterator()
    try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
    await engine.sceneBecameActive()
    while let event = await events.next(), event != .surroundFailed {}
    engine.stop()
}

// PlaybackSessionTests additions (using the file's existing FakeEngine, extended to count disableSurround calls)
@Test func surroundFailureReloadsAtTheCurrentPositionWithoutSpendingRecovery() async {
    // Play to position 300; send .surroundFailed → phase goes through .preparing; one more playback fetch;
    // engine.loads.last?.startAt == 300; then send .failed → the automatic recovery still happens (no error phase).
}
@Test func automaticRecoveryDisablesSurroundFirst() async {
    // Send .failed while playing → engine.disableSurroundCount == 1 before the reload's load call.
}
@Test func expiredURLRecoveryKeepsSurround() async {
    // Advance `now` past urlLifetime, call sceneBecameActive() → a reload happens and engine.disableSurroundCount == 0.
}
@Test func surroundFailureIsIgnoredWhileNotPlaying() async {
    // Send .surroundFailed during .preparing → no extra playback fetch.
}
```

Write the four session tests in full in the style of the neighbouring tests in `PlaybackSessionTests.swift` (they already drive `FakeEngine` events, positions and the fake clock).

- [ ] **Step 2: Run to verify failure** — `UI_TEST AVPlayerEngineTests`, `UI_TEST PlaybackSessionTests`.
- [ ] **Step 3: Implement** as specified. Add the `.surroundFailed` case to every exhaustive `switch` over `PlayerEvent`.
- [ ] **Step 4: Run to verify pass** — both suites in full (all existing session tests must still pass), `UI_BUILD_IOS`, `LINT`.
- [ ] **Step 5: Commit** — `feat(player): reload with original audio when surround fails`

---

### Task 9: Debug signal picker (debug builds only)

**Files:**
- Modify: `Packages/OroroUI/Sources/OroroFeatures/Player/SurroundPolicy.swift`
- Modify: `Packages/OroroUI/Sources/OroroFeatures/Settings/SettingsScreen.swift`
- Test: additions to `SurroundPolicyTests.swift`

**Interfaces:**
- Produces: `enum SurroundDebug { static let defaultsKey = "debug.surroundSignal"; static func signal(in defaults: UserDefaults = .standard) -> SurroundDebugSignal? }` — in release builds always nil. `SurroundPolicy.live` creates its source with `SurroundAudioSource.liveTranscode(signal: SurroundDebug.signal())`.
- Settings (inside `#if DEBUG && os(tvOS)`): a section titled "Debug" with a picker "Surround test signal": Off / Speaker test / Steady tone, bound with `@AppStorage(SurroundDebug.defaultsKey)`. Debug-only strings are verbatim English (`Text(verbatim:)`), not catalogue keys.

- [ ] **Step 1: Write the failing test**

```swift
@Test func debugSignalComesFromDefaults() throws {
    let defaults = try #require(UserDefaults(suiteName: "surround-debug-\(UUID())"))
    #expect(SurroundDebug.signal(in: defaults) == nil)
    defaults.set("speakerTest", forKey: SurroundDebug.defaultsKey)
    #expect(SurroundDebug.signal(in: defaults) == .speakerTest)
    defaults.set("nonsense", forKey: SurroundDebug.defaultsKey)
    #expect(SurroundDebug.signal(in: defaults) == nil)
}
```

- [ ] **Step 2: Run to verify failure** — `UI_TEST SurroundPolicyTests`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run to verify pass** — `UI_TEST SurroundPolicyTests`, `UI_TEST LocalisationTests`, `LINT`.
- [ ] **Step 5: Commit** — `feat(settings): debug picker for surround test signals`

---

### Checkpoint A: first run on the real Apple TV (Max)

Stop here and hand over to Max. Nothing after this point starts until he reports back. What this build is: real 5.1 with seamless joins, the fallback, and a deliberately crude placeholder mix. The rears carry only the *difference* between left and right, so they are nearly silent during plain dialogue: judge the rears with the speaker test, not with a talking scene.

- [ ] Run `mise exec -- tuist generate`, then run the TV app on the Apple TV 4K from Xcode (debug build).
- [ ] **Speaker test.** Settings → Debug → Surround test signal → Speaker test. Play any episode. Expected, repeating every 12 s: centre 1 beep, front left 2, front right 3, rear left 4, rear right 5, subwoofer 6 low beeps. Report which speaker each group came from.
- [ ] **Steady tone.** Switch the signal to Steady tone, play for a minute. Expected: an unbroken tone from the front speakers. Report any tick or stutter (a regular tick every ~4 s means a join defect).
- [ ] **Programme.** Signal Off. Play an episode and a movie for a few minutes each: seek a few times, pause and resume. Report lip sync, any stall, any click, and whether the first second of sound is cut off at the start.
- [ ] **What the Sony's display shows** during Ororo playback and, for comparison, during a 5.1 title in another app.
- [ ] **Console.** In Xcode's console filter on `Surround` and send: the "load" line (output channels, port, surround used or not), any "declined" or "failure" line, and a dozen "segment" lines (transcode ms, total ms).

Reading the results:
- No segment lines and the load line says fewer than 6 channels: tvOS is not offering 5.1 to the app on this chain. Do not change code yet; report the line. Known in-app knob to try next: `AVAudioSession.setPreferredOutputNumberOfChannels(6)` after activation in `AVPlayerEngine.load`.
- Transcode time above 25% of segment duration (about 1 s for a 4 s segment): record the numbers in the spec; Task 10 stays as cheap as specified and the look-ahead may need limiting.
- Beeps from the wrong speakers: the channel order is wrong somewhere between the encoder layout and the output; fix before anything else.

---

### Task 10: The real upmix

**Files:**
- Modify: `Packages/OroroKit/Sources/OroroCore/Playback/SurroundUpmixer.swift`
- Test: additions to `Packages/OroroKit/Tests/OroroCoreTests/SurroundUpmixerTests.swift`

**Interfaces:** unchanged.

Constraints: no dependence on audio older than 3072 frames (Task 4); process sample by sample (chunking test); stay within the speed measured at Checkpoint A.

Design (time-domain, short-memory):

| Channel | Signal |
|---|---|
| C | `0.5 (L + R)` |
| L, R | `L − 0.5·C`, `R − 0.5·C` (a centred voice drops 6 dB in the fronts; a hard-panned sound stays mostly in its own speaker) |
| Ls, Rs | `side = 0.5 (L − R)` → 2nd-order Butterworth high-pass at 100 Hz → 4th-order Butterworth low-pass at 7 kHz → 12 ms delay (576 frames) → gain 0.7071; then `Ls` through a first-order all-pass with coefficient +0.5 and `Rs = −`(the same signal through a first-order all-pass with coefficient −0.5) |
| LFE | `SurroundFormat.lfeGain ×` 4th-order Butterworth low-pass of `0.5 (L + R)` at 120 Hz |

This is a fixed matrix: a hard-panned sound also appears at reduced level in the centre and in antiphase in the opposite front. That is accepted for this round; Checkpoint B listens for it.

- [ ] **Step 1: Write the failing tests** (all Task 3 tests stay and must still pass)

```swift
private static func noise(seed: UInt64, count: Int = 48_000, amplitude: Float = 0.3) -> [Float] {
    var state = seed
    return (0..<count).map { _ in
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return amplitude * (Float((z ^ (z >> 31)) >> 40) / Float(1 << 23) - 1)
    }
}
private static func power(_ channels: [[Float]], from start: Int = 4096) -> Float {
    channels.reduce(0) { $0 + $1[start...].reduce(0) { $0 + $1 * $1 } }
}
private static func correlation(_ a: ArraySlice<Float>, _ b: ArraySlice<Float>) -> Float {
    let dot = zip(a, b).reduce(Float(0)) { $0 + $1.0 * $1.1 }
    return dot / (a.reduce(0) { $0 + $1 * $1 } * b.reduce(0) { $0 + $1 * $1 }).squareRoot()
}

@Test(arguments: [(1 as UInt64, 1 as UInt64), (1, 2)]) // identical channels (centred) and independent channels (wide)
func loudnessStaysCloseToTheStereoInput(leftSeed: UInt64, rightSeed: UInt64) {
    var upmixer = SurroundUpmixer()
    let left = Self.noise(seed: leftSeed), right = Self.noise(seed: rightSeed)
    let frames = upmixer.process(left: left, right: right)
    let ratio = 10 * log10(Self.power(Array(frames.channels.prefix(5))) / Self.power([left, right]))
    #expect(abs(ratio) <= 2)
}
@Test func centredVoiceIsLouderInTheCentreThanInTheFronts() {
    var upmixer = SurroundUpmixer()
    let voice = Self.sine(1000)
    let frames = upmixer.process(left: voice, right: voice)
    #expect(Self.rms(frames.center[24_000...]) > 1.5 * Self.rms(frames.left[24_000...]))
    #expect(Self.rms(frames.center[24_000...]) > 1.5 * Self.rms(frames.right[24_000...]))
}
@Test func hardPannedSoundStaysInItsFrontSpeaker() {
    var upmixer = SurroundUpmixer()
    let frames = upmixer.process(left: Self.sine(1000), right: [Float](repeating: 0, count: 48_000))
    #expect(Self.rms(frames.left[24_000...]) > 2 * Self.rms(frames.right[24_000...]))
    #expect(Self.rms(frames.left[24_000...]) > Self.rms(frames.center[24_000...]))
}
@Test func surroundsAreDelayed() {
    var upmixer = SurroundUpmixer()
    var impulse = [Float](repeating: 0, count: 4096)
    impulse[0] = 1
    let frames = upmixer.process(left: impulse, right: [Float](repeating: 0, count: 4096))
    #expect(frames.leftSurround[..<480].allSatisfy { abs($0) < 1e-4 })   // nothing in the first 10 ms
    #expect(frames.leftSurround[480..<1200].contains { abs($0) > 0.01 }) // arrives by 25 ms
}
@Test func surroundsAreBandLimited() {
    func level(_ hz: Double) -> Float {
        var upmixer = SurroundUpmixer()
        let tone = Self.sine(hz)
        return Self.rms(upmixer.process(left: tone, right: tone.map { -$0 }).leftSurround[24_000...])
    }
    #expect(level(14_000) < 0.1 * level(1000)) // 4th-order low-pass at 7 kHz is about −24 dB an octave up
    #expect(level(40) < 0.3 * level(1000))     // 2nd-order high-pass at 100 Hz is about −16 dB at 40 Hz
}
@Test func surroundsAreDecorrelatedFromEachOther() {
    var upmixer = SurroundUpmixer()
    let wide = Self.noise(seed: 3)
    let frames = upmixer.process(left: wide, right: wide.map { -$0 })
    #expect(abs(Self.correlation(frames.leftSurround[4096...], frames.rightSurround[4096...])) < 0.9)
}
@Test func stateIsShortLived() {
    var upmixer = SurroundUpmixer()
    _ = upmixer.process(left: Self.noise(seed: 4), right: Self.noise(seed: 5))
    let tail = upmixer.process(left: [Float](repeating: 0, count: 8192), right: [Float](repeating: 0, count: 8192))
    #expect(tail.channels.allSatisfy { $0[3072...].allSatisfy { abs($0) < 1e-4 } })
}
```

- [ ] **Step 2: Run to verify failure** — `KIT_TEST SurroundUpmixerTests`.
- [ ] **Step 3: Implement** the table. If a threshold cannot be met with the table as written, change the filter and say so in the commit message; do not loosen the test.
- [ ] **Step 4: Run to verify pass** — `KIT_TEST SurroundUpmixerTests`, then `UI_TEST SurroundTranscoderTests` (joins must still pass with the new filters), `LINT`.
- [ ] **Step 5: Commit** — `feat(core): centre-anchored surround upmix`

---

### Task 11: "Simulated surround" setting

**Files:**
- Modify: `Packages/OroroKit/Sources/OroroCore/Contracts/Library.swift` (`Preferences`)
- Modify: `Packages/OroroUI/Sources/OroroFeatures/Settings/SettingsViewModel.swift`, `SettingsScreen.swift`
- Modify: `Packages/OroroUI/Sources/OroroFeatures/Resources/Localizable.xcstrings`
- Modify: `Packages/OroroUI/Sources/OroroFeatures/Player/PlayerScreen.swift`
- Test: `Packages/OroroKit/Tests/OroroCoreTests/PreferencesCodingTests.swift` (new, suite `PreferencesCodingTests`), additions to `Packages/OroroKit/Tests/OroroStoreTests/LibraryStoreTests.swift` and `SettingsViewModelTests.swift`

**Interfaces:**
- Produces:
  - `Preferences.simulatedSurround: Bool`; `init(subtitleLanguage: String? = "en", autoplayNext: Bool = true, simulatedSurround: Bool = true)`. Do not bump the library's `schemaVersion`.
  - `SettingsViewModel.simulatedSurround: Bool` and `SettingsViewModel.outputIsStereo: Bool` (both `public private(set)`), `public func setSimulatedSurround(_ enabled: Bool) async`. The public initialiser gains `lastOutputChannels: @escaping @MainActor () -> Int? = { AudioOutput.lastObservedChannelCount }`; `load()` sets `outputIsStereo` to true only when that value is non-nil and below 6.
  - `PlayerScreen`: `.live(isEnabled: { await environment.library.snapshot().preferences.simulatedSurround })`.

Copy (exact):

| Key | English | Russian |
|---|---|---|
| `settings.simulatedSurround` | Simulated surround | Имитация объёмного звука |
| `settings.simulatedSurroundStereoOutput` | The current audio output is stereo, so the original sound is used. | Текущий аудиовыход — стерео, поэтому используется исходный звук. |

The toggle goes in the Playback section after "Autoplay next episode", on tvOS only (`#if os(tvOS)`). Convert that `Section` to the `Section { } header: { } footer: { }` form; the footer shows the second string only when `outputIsStereo` is true. The toggle stays operable either way. Strings use `String(localized:defaultValue:bundle: .module)` like the neighbouring rows.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct PreferencesCodingTests {
    @Test func preferencesSavedBeforeSurroundDecodeWithItOn() throws {
        let old = Data(#"{"subtitleLanguage":"ru","autoplayNext":false}"#.utf8)
        #expect(try JSONDecoder().decode(Preferences.self, from: old)
            == Preferences(subtitleLanguage: "ru", autoplayNext: false, simulatedSurround: true))
    }
    @Test func preferencesRoundTripSurroundOff() throws {
        let value = Preferences(subtitleLanguage: nil, autoplayNext: true, simulatedSurround: false)
        #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(value)) == value)
    }
}

// LibraryStoreTests addition
@Test func aLibrarySavedBeforeSurroundLoadsIntact() async throws {
    // Encode a Library with a My List item, one progress entry and Preferences(subtitleLanguage: "ru", autoplayNext: false);
    // strip the "simulatedSurround" key from the JSON; hand the bytes to the store's persistence; load.
    // Expect: myList, progress and the two old preferences unchanged; preferences.simulatedSurround == true;
    // and the store did not take its "back up and start empty" path.
}

// SettingsViewModelTests additions
@Test @MainActor func surroundSettingLoadsAndPersists() async {
    // After load(): simulatedSurround == true. setSimulatedSurround(false) → model false; library preferences false;
    // subtitleLanguage and autoplayNext unchanged.
}
@Test(arguments: [(nil as Int?, false), (2, true), (6, false)])
@MainActor func stereoHintFollowsTheLastPlaybackOutput(channels: Int?, expected: Bool) async {
    // View model built with lastOutputChannels: { channels }; after load(), outputIsStereo == expected.
}
```

Write the three sketched bodies in full in the style of their files.

- [ ] **Step 2: Run to verify failure** — `KIT_TEST PreferencesCodingTests`, `KIT_TEST LibraryStoreTests`, `UI_TEST SettingsViewModelTests`.
- [ ] **Step 3: Implement.** `Preferences` needs a hand-written `init(from:)` with `decodeIfPresent(...) ?? true` for `simulatedSurround`; keep `encode(to:)`, `CodingKeys` and `Hashable` synthesised. (With the synthesised decoder an existing saved library fails to decode and the store starts empty: the user's My List and history would be lost.)
- [ ] **Step 4: Run to verify pass** — the three suites, `UI_TEST LocalisationTests`, `UI_BUILD_IOS`.
- [ ] **Step 5: Run everything** — full `swift test --package-path Packages/OroroKit`, the whole `OroroUI-Package` scheme on the tvOS simulator, `LINT`. Expected: all pass, no lint findings.
- [ ] **Step 6: Commit** — `feat(settings): simulated surround switch`

---

### Checkpoint B: acceptance on the Apple TV and Sony HT-RT4 (Max)

- [ ] Speaker test still correct (Settings → Debug), then signal Off.
- [ ] The Sony shows a 5.1 Dolby Digital input during Ororo playback; sound comes from the rear speakers and the centre; the subwoofer works.
- [ ] **Dialogue scene:** voices sit in the centre. **Music or a wide, busy scene:** the rears carry ambience, not a copy of the fronts. **A sound clearly off to one side:** note whether it also seems to come from behind or from the wrong side (expected weakness of this round).
- [ ] **Bass:** on one bass-heavy scene, toggle Settings → Simulated surround off and on (restart the title each time). The bass should be about the same, not clearly boomier with surround on.
- [ ] No clicks across 10 minutes of playback, three seeks, a pause/resume and a next-episode transition.
- [ ] Lip sync looks right; subtitles, resume and the transport bar behave as before; video quality looks the same as before the feature.
- [ ] Console `Surround` segment lines: transcode time under 25% of segment duration.
- [ ] Pause mid-episode, let the Apple TV sleep for 15 minutes or more, wake it, press play: playback continues (a short reload is acceptable; an error screen is not).
- [ ] With Bluetooth headphones or AirPods connected, start a title: normal stereo, and Settings shows the "current audio output is stereo" note.
- [ ] A movie as well as an episode.

Tuning requests from this checkpoint (rears too loud, centre too narrow, more bass, off-centre sounds wandering) are changes to `SurroundUpmixer` and its tests; steering to keep hard-panned sounds out of the centre is the likely follow-up.

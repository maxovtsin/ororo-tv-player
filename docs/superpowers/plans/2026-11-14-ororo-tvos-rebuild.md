# Ororo Player tvOS Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 2018 UIKit/Carthage app with a SwiftUI tvOS-first Ororo client (plus a basic iOS build) as specified.

**Architecture:** Two local Swift packages — `OroroKit` (no UI: `OroroCore`, `OroroAPI`, `OroroStore`) and `OroroUI` (`OroroDesign`, `OroroFeatures`) — consumed by thin Tuist-generated app targets. One early task freezes every shared type, protocol and view entry point as a compiling stub; after that each task owns a disjoint set of files and replaces its own stubs, so almost everything runs in parallel.

**Tech Stack:** Swift 6.4 (language mode 6, strict concurrency), SwiftUI, AVKit, Swift Testing, Nuke/NukeUI, Tuist, SwiftLint, GitHub Actions. Xcode 27.2, tvOS 26 / iOS 26.

**Spec:** `docs/superpowers/specs/2026-11-13-ororo-tvos-rebuild-design.md` — read it first; this plan does not repeat its behaviour tables.

## Global Constraints

- Deployment targets tvOS 26 / iOS 26; `OroroKit` also declares macOS 26 so `swift test` works.
- Swift 6 language mode, strict concurrency complete. View models are `@MainActor @Observable`; API, repositories and stores are actors; models are `Sendable` structs.
- Only third-party dependency: Nuke / NukeUI. No SwiftData, no CloudKit, no snapshot-test library.
- Dependency direction: `Features → Design, Store → API → Core`. `OroroDesign` imports only SwiftUI and Nuke. Code that needs no SwiftUI import goes in `OroroCore`.
- Never persist a playback URL. Credentials only in Keychain. No credentials or account ids in the repo (fixtures use placeholders).
- Bundle ID `com.dissimirall.Ororo-Player`, team `FYCJCMJ4B5` (free account: no iCloud, no associated domains).
- Every animation uses an `OroroDesign.Motion` token; each has a Reduce Motion variant (`quick` crossfade).
- Every user-facing string is `String(localized: "<key>", defaultValue: "<English>", bundle: .module)`. Feature tasks do **not** create or edit `Localizable.xcstrings` (Task I1 owns it).
- Every focusable element has a VoiceOver label; badge- and icon-only elements read as words ("IMDb rating 8.3", "High definition", country names, "40 percent watched").
- Every view compiles for tvOS and iOS. iOS adaptation per spec: bottom tab bar, shorter hero, stacked detail, context menus for long-press.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`). Each task has its own test file.
- Lint: SwiftLint CLI with the repo's `.swiftlint.yml`; zero errors before commit.
- Constants from the spec, used verbatim: shelf cap 30; hero 6 items, dwell 8 s; watched threshold 0.95; resume prompt only between 60 s and 95%; progress tick 10 s; catalog staleness 6 h; detail cache TTL 10 min; URL considered expired 30 h after fetch; stall timeout 30 s; next-episode action last 40 s, countdown 5 s, "Still watching?" after 3 autoplays; search limit 50 per row, debounce 150 ms; library caps 500 / 200 / 5,000 and 300 KB; image disk cache 500 MB; new-episode resolution max 10 shows per refresh.

## Review Focus

Inputs the spec implies but does not spell out. Each has a test in the owning task.

1. **A list item with a malformed field** (`year: "N/A"`, rating as a string, null `array_genres`) — that field becomes nil/empty and the item still appears; one undecodable item never empties the catalog. → Task A1.
2. **Corrupt or newer-schema library data in `UserDefaults`** — the app starts with an empty library, never crashes, and keeps the unreadable blob under a backup key instead of overwriting it. → Task ST2.
3. **Odd episode numbering** (duplicate numbers, `""`, `"1-2"`, only season 0) — ordering is stable, "next episode" never loops or returns the same episode. → Task C4.
4. **Unknown or zero duration** (HLS reports 0 / NaN early on) — no division by zero, nothing is marked watched, no resume prompt. → Task C5.
5. **A title in My List or in progress disappears from the catalog, then returns** — hidden while absent, no crash, visible again afterwards with its progress. → Task C5.

---

## How to run this in parallel

**Rules**

- Each task runs in its own worktree on branch `task/<ID>`, branched from `redesign/tvos-swiftui` after its dependencies have merged, and merges back when its tests pass.
- A task edits **only** the files in its Files list. `Package.swift` files and everything under a `Contracts/` folder are frozen after Task T3; if a signature must change, stop and ask the coordinator, who makes the change on the main branch.
- Because T3 leaves compiling stubs for every symbol, any later task builds and runs its own tests without waiting for neighbours, unless its "Needs" column lists them.

**Waves**

| Wave | Tasks | Run | Needs |
|---|---|---|---|
| 0 | T1 scaffold, T2 fixtures | T1 ∥ T2 | — |
| 0 | T3 contracts + stubs + fakes | serial | T1, T2 |
| 1 | C1–C7, A1, A2, ST1–ST5, D1–D5 | **17 in parallel** | T3 |
| 1 | S1–S8 spikes (owner + Apple TV) | **8 in parallel**, alongside wave 1 and 2 | T1, T2 |
| 2 | F1–F13 | **13 in parallel** | wave 1 tasks named per task |
| 3 | I1 localisation, I2 app wiring + legacy removal, X* fallbacks | parallel | wave 2; X* need their spike result |
| 4 | I3 iOS acceptance, I4 hardware QA + performance | parallel | everything |

**Spikes do not block the build** (deviation from the spec's "Phase 0 first", chosen for parallelism). Every spike question sits behind a one-file seam, built with the spec's primary choice. If a spike fails, its fallback task `X-Sn` rewrites that one file.

| Spike | Seam file | Fallback task |
|---|---|---|
| S1 focus memory | `OroroDesign/Shelves/ShelfRow.swift` | X-S1 |
| S2 zoom transition | `OroroDesign/Transitions/DetailTransition.swift` | X-S2 |
| S3 hero collapse/paging | `OroroFeatures/Home/HeroView.swift` | X-S3 |
| S4 native subtitles | `OroroFeatures/Player/SubtitleProvider.swift` | X-S4 |
| S5 big grid | `OroroDesign/Shelves/PosterGrid.swift` | X-S5 |
| S6 `youtube://` on tvOS | `OroroFeatures/Detail/TrailerAvailability.swift` | X-S6 |
| S7 glass controls | `OroroDesign/Controls/GlassStyle.swift` | X-S7 |
| S8 durability, ETag | `OroroStore/CatalogRepository.swift` (ETag flag) | X-S8 |

**Commands** (T1 verifies them and corrects this table if a scheme or simulator name differs)

| Name | Command |
|---|---|
| `KIT_TEST <Suite>` | `swift test --package-path Packages/OroroKit --filter <Suite>` |
| `UI_TEST <Suite>` | `cd Packages/OroroUI && xcodebuild test -scheme OroroUI-Package -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' -only-testing:OroroFeaturesTests/<Suite>` (use `OroroDesignTests/<Suite>` for Design) |
| `UI_BUILD_IOS` | `cd Packages/OroroUI && xcodebuild build -scheme OroroUI-Package -destination 'generic/platform=iOS Simulator'` |
| `LINT` | `swiftlint lint --strict` |
| `APPS_BUILD` | `mise exec -- tuist generate --no-open && xcodebuild build -workspace Ororo.xcworkspace -scheme OroroTV -destination 'generic/platform=tvOS Simulator' && xcodebuild build -workspace Ororo.xcworkspace -scheme Ororo -destination 'generic/platform=iOS Simulator'` |

**Standard task cycle.** Unless a task says otherwise its steps are: write the listed tests → run the task's test command and see them fail → implement the listed signatures → run again and see them pass → run `LINT` (and `UI_BUILD_IOS` for `OroroUI` tasks) → commit with the given message.

---

## Wave 0

### Task T1: Tooling and scaffold

**Files:**
- Create: `.mise.toml`, `Tuist.swift`, `Project.swift`, `Packages/OroroKit/Package.swift`, `Packages/OroroUI/Package.swift`, `Apps/TV/OroroTVApp.swift`, `Apps/TV/Info.plist`, `Apps/iOS/OroroApp.swift`, `Apps/iOS/Info.plist`, `.github/workflows/ci.yml`
- Create (one placeholder `.swift` file each so targets build): `Packages/OroroKit/Sources/{OroroCore,OroroAPI,OroroStore}/`, `Packages/OroroKit/Tests/{OroroTestSupport,OroroCoreTests,OroroAPITests,OroroStoreTests}/`, `Packages/OroroUI/Sources/{OroroDesign,OroroFeatures}/`, `Packages/OroroUI/Tests/{OroroDesignTests,OroroFeaturesTests}/`
- Modify: `.gitignore` (add `*.xcodeproj`, `*.xcworkspace`, `Derived/`, `.build/`; fix the stray `øbuild/` line to `build/`), `.swiftlint.yml` (add `included: [Packages, Apps]`; remove `force_cast` from `disabled_rules`)

**Interfaces — Produces:**
- `OroroKit` package: tools-version 6.4; platforms tvOS 26, iOS 26, macOS 26; library products `OroroCore`, `OroroAPI`, `OroroStore`, `OroroTestSupport`; target deps `OroroAPI → OroroCore`, `OroroStore → OroroAPI, OroroCore`, `OroroTestSupport → OroroCore` with `resources: [.copy("Fixtures")]`; all targets `swiftLanguageModes: [.v6]`.
- `OroroUI` package: platforms tvOS 26, iOS 26; depends on `.package(path: "../OroroKit")` and Nuke (latest stable major, pinned in `Package.resolved`); `defaultLocalization: "en"`; products `OroroDesign` (deps `Nuke`, `NukeUI`), `OroroFeatures` (deps `OroroDesign`, `OroroCore`, `OroroStore`, `OroroAPI`), each with `resources: [.process("Resources")]` and an empty `Resources/Localizable.xcstrings` (`{"sourceLanguage":"en","strings":{},"version":"1.0"}`); test targets also depend on `OroroTestSupport`.
- `Project.swift`: targets `OroroTV` (tvOS app) and `Ororo` (iOS app), both bundle id `com.dissimirall.Ororo-Player`, team `FYCJCMJ4B5`, automatic signing, depending on product `OroroFeatures` via `packages: [.package(path: "Packages/OroroUI")]`. tvOS `Info.plist` contains `LSApplicationQueriesSchemes = [youtube]`.
- CI workflow: macOS runner, select Xcode 27; steps `LINT` → `swift test --package-path Packages/OroroKit` → `APPS_BUILD` → `UI_TEST` for all suites. If the runner image lacks Xcode 27, the last two steps carry `if: false` with a comment naming the reason.

- [ ] **Step 1:** Install tooling: `brew install mise swiftlint`, `mise use tuist@latest` (writes `.mise.toml`), `xcodebuild -downloadPlatform tvOS`. Verify: `xcrun simctl list devices available | grep "Apple TV"` prints at least one device.
- [ ] **Step 2:** Create the files above. Each app's `@main` shows `Text("Ororo")` for now.
- [ ] **Step 3:** Run `swift build --package-path Packages/OroroKit`, `UI_BUILD_IOS`, `APPS_BUILD`. Expected: all succeed.
- [ ] **Step 4:** Run `cd Packages/OroroUI && xcodebuild -list`; if the scheme is not `OroroUI-Package` or the simulator name differs, correct the Commands table in this plan.
- [ ] **Step 5:** `LINT` passes. Commit: `chore: scaffold packages, Tuist project and CI`.

### Task T2: Fixtures

**Files:**
- Create: `Scripts/record-fixtures.sh`, `Scripts/trim_fixtures.py`
- Create: `Packages/OroroKit/Tests/OroroTestSupport/Fixtures/{shows,movies,show,episode,movie}.json`, `…/Fixtures/malformed-shows.json`

(The spec says `Tests/Fixtures/`; they sit one level deeper so SwiftPM can bundle them as a resource.)

**Interfaces — Produces:** fixture files named above. `shows.json` / `movies.json` keep their top-level `shows` / `movies` key and hold 200 items each: the 100 with the highest `user_popularity` (shows) or `imdb_rating` (movies), plus 100 taken evenly from the rest, and must include at least 3 items with null `backdrop_url`. `show.json` is MobLand (`/shows/{id}` with 19 episodes), `episode.json` one episode detail, `movie.json` Dune (has `trailer`, 5 `versions`, 4+ subtitles).

- [ ] **Step 1:** Write `trim_fixtures.py <in-dir> <out-dir>`: applies the selection above and replaces every `url` / `download_url` value with `https://example.invalid/stream.m3u8?wmsAuthSign=PLACEHOLDER` and every string containing `wmsAuthSign=` likewise. Subtitle `.vtt` URLs are kept.
- [ ] **Step 2:** Write `record-fixtures.sh`: requires `ORORO_EMAIL` and `ORORO_PASSWORD`, `curl -u` the five endpoints into a temp dir, then calls the trimmer.
- [ ] **Step 3:** Run the trimmer on the existing recordings: `python3 -I Scripts/trim_fixtures.py /private/tmp/claude-501/-Users-max-Projects-ororo/5dc192cb-38d7-45c0-a978-65e820e08a63/scratchpad/api Packages/OroroKit/Tests/OroroTestSupport/Fixtures` (source names there: `shows.json`, `movies.json`, `mobland.json`→`show.json`, `ep.json`→`episode.json`, `dune.json`→`movie.json`). If that folder is gone, run `record-fixtures.sh` instead.
- [ ] **Step 4:** Hand-write `malformed-shows.json`: 4 shows — one valid; one with `"year": "N/A"`, `"imdb_rating": "8.1"`, `"array_genres": null`; one missing `name`; one with `"id": "abc"`.
- [ ] **Step 5:** Verify no secrets: `grep -rE "wmsAuthSign=[^P]|@" Packages/OroroKit/Tests/OroroTestSupport/Fixtures | grep -v PLACEHOLDER` prints nothing. Commit: `test: add scrubbed API fixtures and recording script`.

### Task T3: Contracts, stubs and fakes

Freezes every name other tasks rely on. Bodies are stubs (`[]`, `nil`, `EmptyView()`, `throw APIError.decoding`) except where marked **real**.

**Files:**
- Create in `Packages/OroroKit/Sources/OroroCore/`: `Contracts/Models.swift`, `Contracts/Library.swift`, `Contracts/Shelves.swift`, `Contracts/Protocols.swift`, `Contracts/Route.swift`, and stub files `Shelves/ShelfBuilder.swift`, `Browse/BrowseEngine.swift`, `Search/SearchIndex.swift`, `Episodes/EpisodeOrdering.swift`, `Library/LibraryRules.swift`, `Library/LibraryQueries.swift`, `Playback/SubtitlePlaylistBuilder.swift`, `Display/Display.swift`
- Create in `…/OroroAPI/`: `Decoders.swift`, `Transport.swift`, `LiveOroroAPI.swift` (**real** glue)
- Create in `…/OroroStore/`: `KeychainCredentialStore.swift`, `LibraryStore.swift`, `CatalogRepository.swift`, `DetailRepository.swift`, `NewEpisodeResolver.swift`
- Create in `Packages/OroroKit/Tests/OroroTestSupport/`: `Fixtures.swift`, `Fakes.swift`, `Samples.swift` (all **real**)
- Create in `Packages/OroroUI/Sources/OroroDesign/`: `Contracts/TileModel.swift`, `Contracts/FocusID.swift`, and stub files `Tokens/Motion.swift`, `Tokens/Tokens.swift`, `Images/RemoteImage.swift`, `Images/BackdropView.swift`, `Images/ImageCache.swift`, `Controls/Badge.swift`, `Controls/MetadataLine.swift`, `Controls/ActionButton.swift`, `Controls/Chip.swift`, `Controls/GlassStyle.swift`, `Tiles/Tiles.swift`, `Shelves/FocusMemory.swift`, `Shelves/ShelfRow.swift`, `Shelves/PosterGrid.swift`, `Transitions/DetailTransition.swift`
- Create in `…/OroroFeatures/`: `Contracts/AppEnvironment.swift` (**real**), `Contracts/Navigation.swift` (**real**), `Contracts/Playback.swift`, `Shared/TileModel+Core.swift` (**real**), and one stub screen file per feature: `AppRoot/AppRootView.swift`, `AppRoot/AppSession.swift`, `Home/HomeScreen.swift`, `Home/HeroView.swift`, `Browse/BrowseTabScreen.swift`, `Browse/BrowseGridScreen.swift`, `Detail/DetailScreen.swift`, `Search/SearchScreen.swift`, `MyList/MyListScreen.swift`, `Player/PlayerScreen.swift`, `Player/PlaybackSession.swift`, `SignIn/SignInScreen.swift`, `Settings/SettingsScreen.swift`, `Shared/TitleMenu.swift`
- Test: `Packages/OroroKit/Tests/OroroCoreTests/ContractsTests.swift`

**Interfaces — Produces.** All types are `public`, `Sendable`, and (unless noted) `Hashable, Codable` with a public memberwise `init`.

`OroroCore/Contracts/Models.swift`

```swift
enum TitleKind: String, CaseIterable { case show, movie }
struct TitleID { let kind: TitleKind; let id: Int }
enum Resolution: String { case sd = "SD", hd = "HD" }
struct Title: Identifiable {
    let id: TitleID
    var name: String
    var desc: String?
    var posterURL: URL?, backdropURL: URL?
    var imdbRating: Double?, imdbID: String?
    var year: Int?
    var genres: [String], countries: [String]      // countries are ISO-2
    var lengthMinutes: Int?
    var resolution: Resolution?                     // movies only
    var ended: Bool?                                // shows only
    var popularity: Int                             // 0 = unknown; always 0 for movies
    var newestVideo: Date?                          // shows only
    var updatedAt: Date?
}
struct Episode: Identifiable {
    let id: Int; let showID: Int
    var name: String?, plot: String?
    var season: Int; var number: Int?               // nil when the API string is not numeric
    var airdate: Date?; var resolution: Resolution?
    var qualities: [String]                         // keys of `versions`, e.g. ["240p","720p"]
}
struct Subtitle { let lang: String; let url: URL }
struct Playback { let streamURL: URL; let subtitles: [Subtitle]; let fetchedAt: Date }   // not Codable
struct ShowDetail { var title: Title; var seasonCount: Int?; var episodes: [Episode] }
struct MovieDetail { var title: Title; var trailerYouTubeID: String?; var qualities: [String]; var subtitleLanguages: [String]; var playback: Playback? }   // not Codable
struct EpisodeDetail { var episode: Episode; var showName: String?; var subtitleLanguages: [String]; var playback: Playback? }                              // not Codable
struct Catalog {                                    // not Codable
    let shows: [Title]; let movies: [Title]; let fetchedAt: Date
    func title(_ id: TitleID) -> Title?             // real: dictionary lookup built in init
    func titles(_ kind: TitleKind) -> [Title]
}
struct Credentials { let email: String; let password: String }   // Equatable, not Codable
enum APIError: Error, Equatable { case unauthorized, offline, notFound, server(status: Int), decoding }
```

`OroroCore/Contracts/Library.swift`

```swift
enum PlayableKind: String { case movie, episode }
struct PlayableID { let kind: PlayableKind; let id: Int }
struct MyListItem { let title: TitleID; let addedAt: Date }
struct ProgressEntry {
    let playable: PlayableID
    var showID: Int?, season: Int?, number: Int?, episodeName: String?
    var position: TimeInterval, duration: TimeInterval, updatedAt: Date
}
struct EpisodeRef { let episodeID: Int; let season: Int; let number: Int }
struct UpNextEntry { let ref: EpisodeRef; let setAt: Date }
struct FollowState { var seenNewestVideo: Date; var started: Bool }
struct Preferences { var subtitleLanguage: String? = "en"; var autoplayNext: Bool = true }   // nil language = Off
struct Library {
    var schemaVersion: Int = 1
    var myList: [MyListItem] = []
    var progress: [ProgressEntry] = []
    var watchedEpisodes: [Int] = [], watchedMovies: [Int] = []   // insertion order, no duplicates
    var upNext: [Int: UpNextEntry] = [:]                          // key: show id
    var followed: [Int: FollowState] = [:]                        // key: show id
    var preferences = Preferences()
}
struct ShowContext { let showID: Int; let season: Int; let number: Int; let episodeName: String?; let newestVideo: Date? }
struct NewEpisodeInfo { let first: EpisodeRef; let count: Int }
```

`OroroCore/Contracts/Shelves.swift`

```swift
enum ShelfKind { case continueWatching, newEpisodes, popularShows, latestReleases, topRatedMovies,
                 recentlyUpdatedMovies, myList, popularNow, topRated, recentlyUpdated, genre(String) }
enum ShelfBadge { case new, newCount(Int), newSince(Date) }
struct ShelfItem: Identifiable {
    var id: String { "\(title.id.kind.rawValue)-\(title.id.id)" }
    let title: Title
    var progress: Double?            // 0...1
    var episode: EpisodeRef?
    var badge: ShelfBadge?
    var playable: PlayableID?        // set when Select should play directly
}
struct Shelf: Identifiable { let id: String; let kind: ShelfKind; var items: [ShelfItem]; var totalCount: Int; var seeAll: BrowseQuery? }
enum HeroAction { case playMovie, playFirstEpisode, playEpisode(EpisodeRef), resumeEpisode(EpisodeRef) }
struct HeroItem: Identifiable { var id: TitleID { title.id }; let title: Title; var action: HeroAction }
struct HomeContent { var hero: [HeroItem]; var shelves: [Shelf] }
struct BrowseQuery {
    enum Status: String { case ongoing, ended }
    enum Sort: String, CaseIterable { case popular, rating, year, recentlyUpdated, alphabetical }
    var kind: TitleKind; var genre: String?; var decade: Int?; var minRating: Double?; var status: Status?; var sort: Sort
    static func `default`(_ kind: TitleKind) -> BrowseQuery   // real: .popular for shows, .recentlyUpdated for movies
}
struct SearchResults { var shows: [Title]; var movies: [Title] }
```

`OroroCore/Contracts/Route.swift`: `enum Route { case show(Int), movie(Int), browse(BrowseQuery) }`

`OroroCore/Contracts/Protocols.swift`

```swift
enum Conditional<T: Sendable>: Sendable { case notModified, fresh(T) }
struct ListResponse: Sendable { let titles: [Title]; let rawData: Data; let etag: String? }
protocol OroroAPI: Sendable {
    func shows(_ c: Credentials, ifNoneMatch: String?, progress: (@Sendable (Double) -> Void)?) async throws -> Conditional<ListResponse>
    func movies(_ c: Credentials, ifNoneMatch: String?, progress: (@Sendable (Double) -> Void)?) async throws -> Conditional<ListResponse>
    func show(id: Int, _ c: Credentials) async throws -> ShowDetail
    func movie(id: Int, _ c: Credentials) async throws -> MovieDetail
    func episode(id: Int, _ c: Credentials) async throws -> EpisodeDetail
}
protocol CredentialStoring: Sendable { func load() -> Credentials?; func save(_ c: Credentials) throws; func clear() throws }
protocol CatalogProviding: Sendable {
    func current() async -> Catalog?
    func lastUpdated() async -> Date?
    func signIn(_ c: Credentials, progress: (@Sendable (Double) -> Void)?) async throws -> Catalog   // fetches, caches, stores credentials
    func loadCached() async -> Catalog?                                // decode cache files; nil if none
    func refresh(force: Bool, now: Date) async throws -> Bool          // true when a new catalog was swapped in
    func homeSnapshot() async -> HomeContent?
    func saveHomeSnapshot(_ content: HomeContent) async
    func clear() async
}
protocol LibraryStoring: Sendable {
    func snapshot() async -> Library
    func update(_ mutate: @Sendable (inout Library) -> Void) async     // memory now, throttled flush
    func flush() async
    func erase() async
    func updates() async -> AsyncStream<Library>
}
protocol DetailProviding: Sendable {
    func show(id: Int) async throws -> ShowDetail                      // cached
    func movie(id: Int) async throws -> MovieDetail                    // cached, playback == nil
    func episode(id: Int) async throws -> EpisodeDetail                // cached, playback == nil
    func moviePlayback(id: Int) async throws -> MovieDetail            // always network
    func episodePlayback(id: Int) async throws -> EpisodeDetail        // always network
    func clear() async
}
protocol NewEpisodeResolving: Sendable {
    func cached() async -> [Int: NewEpisodeInfo]
    func resolve(shows: [Title], library: Library) async -> [Int: NewEpisodeInfo]
}
```

Core logic stubs (signatures are given in the task that implements each: C1–C7).

`OroroAPI`: `enum Decoders` (A1), `struct Transport` (A2), and **real** `struct LiveOroroAPI: OroroAPI { init(transport: Transport) }` whose five methods call `transport` then `Decoders`.

`OroroStore` stubs: `final class KeychainCredentialStore: CredentialStoring`, `actor LibraryStore: LibraryStoring`, `actor CatalogRepository: CatalogProviding`, `actor DetailRepository: DetailProviding`, `actor NewEpisodeResolver: NewEpisodeResolving` (inits in ST1–ST5).

`OroroTestSupport` (**real**): `enum Fixtures { static func data(_ name: String) -> Data }`; `enum Samples { static let catalog: Catalog; static func show(_ id: Int, popularity: Int = 0, newestVideo: Date? = nil, …) -> Title; static func movie(…) -> Title; static func episodes(showID: Int, seasons: [Int: Int]) -> [Episode] }` (`catalog` is built by hand, not decoded, so it works before A1 lands); `actor FakeAPI: OroroAPI` (settable results per method, call counters); `actor InMemoryLibraryStore: LibraryStoring`; `actor FakeCatalog: CatalogProviding`; `actor FakeDetails: DetailProviding`; `final class InMemoryCredentialStore: CredentialStoring`; `actor FakeNewEpisodes: NewEpisodeResolving`.

`OroroDesign/Contracts`

```swift
public enum TileShape: Sendable { case poster, landscape }
public enum BadgeKind: Hashable, Sendable { case imdb(Double), hd, sd, cc, new, text(String) }
public struct TileModel: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String, subtitle: String?
    public var posterURL: URL?, backdropURL: URL?
    public var progress: Double?, badge: BadgeKind?
    public var accessibilityLabel: String
}
public struct FocusID: Hashable, Sendable { public let screen: String, shelf: String, item: String }
```

Design stubs (signatures in D1–D5): `Motion`, `Spacing`, `Typography`, `Palette`, `RemoteImage`, `BackdropView`, `ImageCache`, `Badge`, `MetadataLine`, `ActionButton`, `Chip`, `GlassStyle`, `PosterTile`, `LandscapeTile`, `SkeletonTile`, `FocusMemory`, `ShelfRow`, `PosterGrid`, `detailZoomSource` / `detailZoomDestination`.

`OroroFeatures/Contracts` (**real**)

```swift
public struct AppEnvironment: Sendable {
    public let api: any OroroAPI, catalog: any CatalogProviding, library: any LibraryStoring
    public let details: any DetailProviding, credentials: any CredentialStoring, newEpisodes: any NewEpisodeResolving
    public static func live() -> AppEnvironment          // builds the OroroStore types
    public static func preview() -> AppEnvironment       // DEBUG only, in-file minimal fakes
}
extension EnvironmentValues { @Entry public var appEnvironment: AppEnvironment }
public enum AppTab: Hashable, CaseIterable, Sendable { case home, shows, movies, myList, search, settings }
@MainActor @Observable public final class TabRouter {
    public var path: [Route] = []; public let focus = FocusMemory()
    public var isAtTop = true                 // each tab's root screen keeps this current
    public var scrollToTopToken = 0           // F1 increments on Menu at a scrolled root; root screens observe it, scroll to top and focus their first element
    public func push(_ route: Route); public func open(_ id: TitleID)   // .show / .movie
}
extension EnvironmentValues { @Entry public var selectTab: @MainActor (AppTab) -> Void }   // provided by F1
public struct PlayRequest: Identifiable, Hashable, Sendable {
    public enum Target: Hashable, Sendable { case movie(Int), episode(id: Int, showID: Int), show(Int) }   // .show = resume, else up-next, else first
    public let id: UUID; public let target: Target; public var startOver: Bool
}
@MainActor @Observable public final class PlaybackLauncher {
    public var active: PlayRequest?                      // AppRoot presents PlayerScreen while non-nil
    public var lastPlayed: PlayableID?                   // set by the player on dismissal
    public func play(_ target: PlayRequest.Target, startOver: Bool = false)
}
@MainActor public protocol PlayerEngine: AnyObject {
    var events: AsyncStream<PlayerEvent> { get }
    func load(_ playback: Playback, startAt: TimeInterval, subtitleLanguage: String?) async throws
    func play(); func pause(); func seek(to: TimeInterval) async
    var position: TimeInterval { get }; var duration: TimeInterval { get }
}
public enum PlayerEvent: Sendable, Equatable {
    case time(position: TimeInterval, duration: TimeInterval), paused, resumed, ended, failed
    case stalled(seconds: TimeInterval), subtitleChanged(String?), userInput
}
```

Screen entry points (stubs showing their own name): `AppRootView()`, `HomeScreen()`, `HeroView(items:isExpanded:isInList:onPlay:onToggleList:)`, `BrowseTabScreen(kind:)`, `BrowseGridScreen(query:)`, `DetailScreen(id: TitleID)`, `SearchScreen()`, `MyListScreen()`, `PlayerScreen(request:)`, `SignInScreen()`, `SettingsScreen()`, `titleMenu(for:context:)`. Screens read `@Environment(\.appEnvironment)`, `@Environment(TabRouter.self)`, `@Environment(PlaybackLauncher.self)`, `@Environment(AppSession.self)`.

`Shared/TileModel+Core.swift` (**real**): `extension TileModel { init(_ title: Title, locale: Locale = .current); init(_ item: ShelfItem, locale: Locale = .current) }` — subtitle is the year for titles; for shelf items with an episode it is `"S2 E5"`; badge maps `.new`/`.newCount`/`.newSince` to `.new`; accessibility label is "name, year, IMDb rating x, n percent watched" with absent parts omitted.

- [ ] **Step 1:** Write `ContractsTests`:

```swift
@Test func libraryRoundTripsThroughJSON() throws {
    var lib = Library()
    lib.upNext[7] = UpNextEntry(ref: EpisodeRef(episodeID: 1, season: 1, number: 2), setAt: Date(timeIntervalSince1970: 50))
    lib.followed[7] = FollowState(seenNewestVideo: Date(timeIntervalSince1970: 100), started: true)
    let back = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(lib))
    #expect(back == lib)
}
@Test func catalogLooksUpByID() {
    #expect(Samples.catalog.title(Samples.catalog.shows[0].id) == Samples.catalog.shows[0])
    #expect(Samples.catalog.title(TitleID(kind: .movie, id: -1)) == nil)
}
@Test func defaultQuerySortDependsOnKind() {
    #expect(BrowseQuery.default(.show).sort == .popular)
    #expect(BrowseQuery.default(.movie).sort == .recentlyUpdated)
}
@Test func fixturesLoad() { #expect(Fixtures.data("shows").count > 1000) }
```

- [ ] **Step 2:** `KIT_TEST ContractsTests` → fails to compile.
- [ ] **Step 3:** Create every file listed, with the signatures above and the stub signatures from tasks C1–C7, A1–A2, ST1–ST5, D1–D5 and F1–F13.
- [ ] **Step 4:** `KIT_TEST ContractsTests` passes; `swift build --package-path Packages/OroroKit`, `UI_BUILD_IOS` and `APPS_BUILD` succeed; `LINT` passes.
- [ ] **Step 5:** Point both `@main` apps at `AppRootView().environment(\.appEnvironment, .live())`. Commit: `feat: freeze contracts with compiling stubs and test fakes`.

---

## Wave 1 — Core (pure logic, `swift test`)

All Core tasks: files under `Packages/OroroKit/Sources/OroroCore/`, tests under `Packages/OroroKit/Tests/OroroCoreTests/`, test data from `Samples`. Needs: T3 only.

### Task C1: Shelf builder

**Files:** Modify `Shelves/ShelfBuilder.swift`. Test `ShelfBuilderTests.swift`.

**Interfaces — Produces:**

```swift
public enum ShelfBuilder {
    public static let shelfCap = 30
    public static func hero(catalog: Catalog, now: Date) -> [Title]                       // 6: 3 shows + 3 movies, interleaved show first
    public static func home(catalog: Catalog, hero: [HeroItem], continueWatching: [ShelfItem],
                            newEpisodes: [ShelfItem], myList: [Title], now: Date) -> HomeContent
    public static func browseTab(kind: TitleKind, catalog: Catalog) -> [Shelf]
    public static func genresByCount(_ titles: [Title]) -> [(genre: String, count: Int)]
}
```

Decisions: hero shows = highest `popularity` with `newestVideo` within 30 days of `now`; hero movies = highest `imdbRating` with `updatedAt` within 30 days; both require `backdropURL` and non-empty `desc`; if fewer than 3 qualify, widen the window to all time. Home shelf order and kinds exactly as the spec's list of 8 (4 genre rows = largest genres across shows + movies); personal shelves are omitted when empty. Top Rated (both) requires `year >= currentYear - 20`; for shows it also requires `popularity > 0`. `seeAll` is a `BrowseQuery` pre-set to the row (genre, or sort). `totalCount` is the uncapped count. Shelf `id` is stable: kind name, or `"genre-<name>"`.

- [ ] **Step 1: Tests**

```swift
@Test func homeOrderAndHiddenRows() {
    let c = ShelfBuilder.home(catalog: Samples.catalog, hero: [], continueWatching: [], newEpisodes: [], myList: [], now: Samples.now)
    #expect(c.shelves.map(\.id).prefix(4) == ["popularShows", "latestReleases", "topRatedMovies", "recentlyUpdatedMovies"])
    #expect(c.shelves.count == 8)                                  // 4 fixed + 4 genres
}
@Test func personalRowsComeFirstWhenPresent()   // continueWatching, newEpisodes at 0,1; myList after recentlyUpdatedMovies
@Test func shelvesAreCappedAt30ButReportTotal() // items.count == 30, totalCount > 30
@Test func popularShowsSortedByPopularityDesc()
@Test func latestReleasesSortedByNewestVideoDesc()
@Test func heroHasThreeShowsThreeMoviesAllWithBackdropAndDesc()
@Test func heroWidensWindowWhenNothingRecent()   // now far in the future still yields 6
@Test func browseTabShows()  // ids: popularNow, latestReleases, topRated, then genre-* by count desc
@Test func browseTabMovies() // ids: recentlyUpdated, topRated, then genre-*
@Test func seeAllQueryMatchesRow() // genre row → query.genre == that genre, kind matches
```

- [ ] **Steps 2–5:** standard cycle with `KIT_TEST ShelfBuilderTests`. Commit: `feat(core): shelf and hero builder`.

### Task C2: Browse filter and sort

**Files:** Modify `Browse/BrowseEngine.swift`. Test `BrowseEngineTests.swift`.

**Interfaces — Produces:**

```swift
public enum BrowseEngine {
    public static func apply(_ query: BrowseQuery, to catalog: Catalog) -> [Title]
    public static func genres(for kind: TitleKind, in catalog: Catalog) -> [String]   // by title count desc
    public static func decades(for kind: TitleKind, in catalog: Catalog) -> [Int]     // e.g. [2020, 2010, …]
}
```

Decisions: `decade` 1990 matches years 1990–1999; titles with nil year fail a decade filter; nil rating fails any `minRating`; `status` is ignored for movies; `.popular` puts `popularity == 0` after the rest ordered by rating desc; `.year` is year desc then `updatedAt` desc; `.alphabetical` uses `localizedStandardCompare`; every sort breaks final ties by `id.id` so output is deterministic.

- [ ] **Step 1: Tests** — `genreFilter`, `decadeFilterBounds` (1989 out, 1990 and 1999 in, 2000 out), `minRatingExcludesNil`, `statusOngoingAndEnded`, `statusIgnoredForMovies`, `popularSortPutsZeroPopularityLastByRating`, `yearSort`, `recentlyUpdatedSort`, `alphabeticalSortIsCaseAndDiacriticInsensitive`, `combinedFiltersIntersect`, `noMatchReturnsEmpty`, `sortIsDeterministic` (apply twice on shuffled input → equal).
- [ ] **Steps 2–5:** standard cycle with `KIT_TEST BrowseEngineTests`. Commit: `feat(core): browse filtering and sorting`.

### Task C3: Search index

**Files:** Modify `Search/SearchIndex.swift`. Test `SearchIndexTests.swift`.

**Interfaces — Produces:**

```swift
public struct SearchIndex: Sendable {
    public init(catalog: Catalog)
    public func search(_ query: String, limit: Int = 50) -> SearchResults
}
```

Decisions: fold = lowercase + strip diacritics + collapse whitespace. Rank tiers: exact title (0), title prefix (1), any-word prefix (2), substring (3), genre name equals query (4), year equals a 4-digit query (5). Within a tier: shows by popularity desc, movies by rating desc. Empty or whitespace-only query returns empty results.

- [ ] **Step 1: Tests** — `exactBeatsPrefixBeatsWordBeatsSubstring`, `diacriticsAndCaseIgnored` ("amelie" finds "Amélie"), `genreQueryReturnsGenreTitles`, `yearQueryReturnsThatYear`, `tieBreakByPopularityForShowsAndRatingForMovies`, `limitApplied`, `emptyAndWhitespaceQueryReturnsNothing`, `specialCharactersDoNotCrash` (`"("`, `"\\"`, `"🙂"`, 500-character string → no crash, empty or valid results).
- [ ] **Steps 2–5:** standard cycle with `KIT_TEST SearchIndexTests`. Commit: `feat(core): search index and ranking`.

### Task C4: Episode ordering

**Files:** Modify `Episodes/EpisodeOrdering.swift`. Test `EpisodeOrderingTests.swift`.

**Interfaces — Produces:**

```swift
public enum EpisodeOrdering {
    public static func seasons(_ episodes: [Episode]) -> [Int]                          // ascending, 0 ("Specials") last
    public static func episodes(_ episodes: [Episode], season: Int) -> [Episode]        // by number; nil numbers last in original order
    public static func ordered(_ episodes: [Episode]) -> [Episode]                      // all seasons in play order, specials excluded
    public static func next(after episodeID: Int, in episodes: [Episode]) -> Episode?   // nil at the end, or if id is a special/unknown
    public static func first(in episodes: [Episode]) -> Episode?
    public static func unwatched(after lastWatchedID: Int?, in episodes: [Episode], watched: Set<Int>) -> [Episode]
    public static func initialSeason(episodes: [Episode], resume: EpisodeRef?) -> Int?
    public static func qualityRange(_ episodes: [Episode]) -> (lowest: String, highest: String)?   // by numeric value of "720p"
    public static func ref(_ episode: Episode) -> EpisodeRef?                            // nil when number is nil
}
```

- [ ] **Step 1: Tests** — `seasonsSortedWithSpecialsLast`, `episodesSortedNumerically` (10 after 9), `nextWithinSeason`, `nextCrossesToNextSeason`, `nextAtSeriesEndIsNil`, `nextNeverReturnsSpecial`, `initialSeasonUsesResumeElseFirst`, `qualityRangeAcrossEpisodes` (240p…1080p), plus Review Focus 3:

```swift
@Test func oddNumberingIsStableAndNeverLoops() {
    var eps = Samples.episodes(showID: 1, seasons: [1: 4])
    eps[1].number = eps[0].number          // duplicate
    eps[2].number = nil                    // "" or "1-2" decoded as nil
    var seen = Set<Int>(); var cur = EpisodeOrdering.first(in: eps)
    while let e = cur { #expect(seen.insert(e.id).inserted); cur = EpisodeOrdering.next(after: e.id, in: eps) }
    #expect(seen.count == 4)
    #expect(EpisodeOrdering.ordered(eps) == EpisodeOrdering.ordered(eps.reversed().reversed()))
}
@Test func onlySpecialsShow() {            // every episode in season 0
    let eps = Samples.episodes(showID: 1, seasons: [0: 3])
    #expect(EpisodeOrdering.seasons(eps) == [0]); #expect(EpisodeOrdering.first(in: eps) == nil)
    #expect(EpisodeOrdering.initialSeason(episodes: eps, resume: nil) == 0)
}
```

- [ ] **Steps 2–5:** standard cycle with `KIT_TEST EpisodeOrderingTests`. Commit: `feat(core): episode ordering and next-episode`.

### Task C5: Library rules and queries

**Files:** Modify `Library/LibraryRules.swift`, `Library/LibraryQueries.swift`. Test `LibraryRulesTests.swift`, `LibraryQueriesTests.swift`.

**Interfaces — Produces:**

```swift
public extension Library {
    static let watchedThreshold = 0.95, resumeMinimum: TimeInterval = 60
    static let maxMyList = 500, maxProgress = 200, maxWatched = 5_000

    func isInMyList(_ id: TitleID) -> Bool
    mutating func toggleMyList(_ id: TitleID, newestVideo: Date?, now: Date)     // adding a show follows it
    mutating func recordProgress(_ p: PlayableID, show: ShowContext?, position: TimeInterval, duration: TimeInterval, now: Date)
    mutating func finish(_ p: PlayableID, show: ShowContext?, next: EpisodeRef?, now: Date)
    mutating func markWatched(_ p: PlayableID); mutating func markUnwatched(_ p: PlayableID)
    mutating func removeFromContinueWatching(_ id: TitleID)                       // clears progress + upNext for that title; watched flags stay
    mutating func dismissNewEpisodes(showID: Int, newestVideo: Date)
    mutating func prune()                                                          // enforce caps, oldest first

    func isWatched(_ p: PlayableID) -> Bool
    func fraction(_ p: PlayableID) -> Double?                                      // nil when no entry or duration <= 0
    func resumePosition(_ p: PlayableID) -> TimeInterval?                          // only when position > 60 and fraction < 0.95
    func shouldMarkWatched(position: TimeInterval, duration: TimeInterval) -> Bool
}
public enum LibraryQueries {
    public static func continueWatching(_ library: Library, catalog: Catalog) -> [ShelfItem]
    public static func showsWithNewEpisodes(_ library: Library, catalog: Catalog) -> [Title]     // includes those in Continue Watching
    public static func newEpisodes(_ library: Library, catalog: Catalog, resolved: [Int: NewEpisodeInfo]) -> [ShelfItem]
    public static func myList(_ library: Library, catalog: Catalog) -> [Title]                   // newest first
    public static func heroAction(for title: Title, library: Library) -> HeroAction
    public static func resumeTarget(showID: Int, library: Library) -> EpisodeRef?               // in-progress, else upNext
}
```

Decisions:
- `recordProgress` with a `ShowContext` sets `followed[showID]` to `started: true` and `seenNewestVideo = show.newestVideo ?? existing ?? now`. It replaces any existing entry for the same playable, and removes other in-progress entries of the same show (one entry per show).
- `finish` marks watched, removes the progress entry, sets `upNext[showID] = UpNextEntry(ref: next, setAt: now)` or removes it when `next` is nil.
- Removing a show from My List un-follows it only when `started == false`.
- A show "has new episodes" when it is followed and `title.newestVideo > seenNewestVideo`.
- `continueWatching`: one item per in-progress movie and one per show (its in-progress entry, else its `upNext`), sorted by last activity desc (`ProgressEntry.updatedAt`, or `UpNextEntry.setAt` for up-next-only shows). Items carry `progress`, `episode`, `playable`; a show that also has new episodes gets `badge: .new`.
- `newEpisodes`: `showsWithNewEpisodes` minus shows present in `continueWatching`, sorted by `newestVideo` desc, max 30. With a resolved entry: `episode = first`, `playable = episode`, `badge = count > 1 ? .newCount(count) : .new`. Unresolved: `badge = .newSince(newestVideo)`, `playable = nil`. Shows with `started == false` always have `playable = nil` (Select opens Detail).
- `heroAction`: movies → `.playMovie`; shows → `.resumeEpisode` if in progress, `.playEpisode` if up-next, else `.playFirstEpisode`.
- Queries silently skip ids missing from the catalog and never delete them.

- [ ] **Step 1: Tests** — `toggleMyListAddsThenRemoves`, `addingShowFollowsIt`, `removingUnstartedShowUnfollows`, `removingStartedShowStaysFollowed`, `recordProgressReplacesSamePlayableAndOtherEpisodeOfShow`, `finishMarksWatchedSetsUpNext`, `finishLastEpisodeRemovesShowFromContinueWatching`, `finishMovieLeavesContinueWatching`, `resumePositionOnlyBetween60sAnd95Percent` (59 s → nil, 61 s → value, 96% → nil), `continueWatchingOneEntryPerShowSortedByActivity`, `newEpisodeDetectedWhenNewestVideoAdvances`, `showInContinueWatchingGetsBadgeNotSecondRow`, `resolvedNewEpisodeIsPlayableWithCountBadge`, `unstartedMyListShowIsNotDirectlyPlayable`, `startingNewEpisodeMovesShowToContinueWatching`, `dismissClearsNewFlag`, `pruneEnforcesCapsOldestFirst`, `heroActionForEachState`, plus Review Focus 4 and 5:

```swift
@Test func zeroOrNaNDurationIsSafe() {
    var lib = Library(); let p = PlayableID(kind: .movie, id: 1)
    lib.recordProgress(p, show: nil, position: 500, duration: 0, now: Samples.now)
    #expect(lib.fraction(p) == nil); #expect(lib.resumePosition(p) == nil)
    #expect(!lib.shouldMarkWatched(position: 500, duration: 0))
    #expect(!lib.shouldMarkWatched(position: 500, duration: .nan))
    #expect(LibraryQueries.continueWatching(lib, catalog: Samples.catalog).first?.progress == nil)
}
@Test func titleMissingFromCatalogIsHiddenThenReturns() {
    var lib = Library(); let ghost = TitleID(kind: .movie, id: 999_999)
    lib.toggleMyList(ghost, newestVideo: nil, now: Samples.now)
    lib.recordProgress(PlayableID(kind: .movie, id: 999_999), show: nil, position: 120, duration: 6000, now: Samples.now)
    #expect(LibraryQueries.myList(lib, catalog: Samples.catalog).isEmpty)
    #expect(LibraryQueries.continueWatching(lib, catalog: Samples.catalog).isEmpty)
    let bigger = Catalog(shows: Samples.catalog.shows, movies: Samples.catalog.movies + [Samples.movie(999_999)], fetchedAt: Samples.now)
    #expect(LibraryQueries.myList(lib, catalog: bigger).count == 1)
    #expect(LibraryQueries.continueWatching(lib, catalog: bigger).first?.progress == 0.02)
}
```

- [ ] **Steps 2–5:** standard cycle with `KIT_TEST LibraryRulesTests` and `KIT_TEST LibraryQueriesTests`. Commit: `feat(core): library rules, continue watching and new episodes`.

### Task C6: Subtitle playlist builder

**Files:** Modify `Playback/SubtitlePlaylistBuilder.swift`. Test `SubtitlePlaylistBuilderTests.swift`.

**Interfaces — Produces:**

```swift
public enum SubtitlePlaylistBuilder {
    public static let scheme = "ororo-subs", groupID = "subs"
    public static func masterURL() -> URL                                  // ororo-subs://master.m3u8
    public static func subtitleURL(lang: String) -> URL                    // ororo-subs://subtitles/<lang>.m3u8
    public static func language(from url: URL) -> String?
    public static func master(original: String, originalURL: URL, subtitles: [Subtitle], defaultLanguage: String?) -> String
    public static func subtitlePlaylist(vttURL: URL, duration: TimeInterval) -> String
}
```

Decisions: `master` keeps every original line; rewrites each URI line and each `URI="…"` attribute to an absolute URL resolved against `originalURL` (an already-absolute URI is unchanged, including its query string); appends `SUBTITLES="subs"` to every `#EXT-X-STREAM-INF` line that lacks a `SUBTITLES` attribute; inserts one `#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="<localised language name in English>",LANGUAGE="<lang>",AUTOSELECT=YES,DEFAULT=<YES for defaultLanguage else NO>,URI="ororo-subs://subtitles/<lang>.m3u8"` per subtitle after `#EXTM3U`. With no subtitles the output only has rewritten URIs. A media (non-master) playlist — no `#EXT-X-STREAM-INF` — is wrapped: a one-variant master pointing at `originalURL` plus the subtitle entries. `subtitlePlaylist` is a VOD playlist with `#EXT-X-TARGETDURATION` = ceil(duration), one `#EXTINF:<duration>,` segment = the `.vtt` URL, and `#EXT-X-ENDLIST`. Duplicate languages keep the first.

- [ ] **Step 1: Tests** — `relativeVariantURIsBecomeAbsolute`, `absoluteURIWithQueryIsUntouched` (keeps `wmsAuthSign=PLACEHOLDER`), `uriAttributesInMediaTagsAreRewritten`, `streamInfGetsSubtitlesGroup`, `oneMediaEntryPerLanguageWithDefaultFlag`, `noSubtitlesProducesNoMediaEntries`, `mediaPlaylistIsWrappedInMaster`, `subtitlePlaylistShape` (exact expected string for duration 2700.4), `duplicateLanguagesKeepFirst`, `languageRoundTripsThroughURL`, `crlfInputIsHandled`.
- [ ] **Steps 2–5:** standard cycle with `KIT_TEST SubtitlePlaylistBuilderTests`. Commit: `feat(core): HLS subtitle playlist builder`.

### Task C7: Display formatting

**Files:** Modify `Display/Display.swift`. Test `DisplayTests.swift`.

**Interfaces — Produces:**

```swift
public enum Display {
    public static func runtime(minutes: Int, locale: Locale) -> String                    // en: "2h 35m", "45m"
    public static func flag(_ iso2: String) -> String?                                    // nil unless 2 ASCII letters
    public static func countryName(_ iso2: String, locale: Locale) -> String?
    public static func languageName(_ code: String, locale: Locale) -> String             // falls back to uppercased code
    public static func episodeLabel(season: Int, number: Int) -> String                   // "S2 E5"
    public static func airdate(_ date: Date, locale: Locale) -> String                    // en: "30 Mar 2025"
    public static func newEpisodeAgo(_ date: Date, now: Date, locale: Locale) -> String?  // nil when older than 14 days or in the future
    public static func timecode(_ seconds: TimeInterval) -> String                        // "23:14", "1:02:03"
    public static func seasonCount(_ n: Int, locale: Locale) -> String                    // "1 Season", "2 Seasons"
    public static func qualityRange(lowest: String, highest: String) -> String            // "240p–1080p"; same → "720p"
}
```

Uses `Duration.UnitsFormatStyle`, `Date.FormatStyle`, `Date.RelativeFormatStyle`, `Locale.localizedString`.

- [ ] **Step 1: Tests** — one test per function with `Locale(identifier: "en_GB")` values above, plus `runtimeInRussianIsLocalised` (not equal to the English string), `flagRejectsBadCodes` (`""`, `"GBR"`, `"1A"` → nil), `timecodeHandlesNaNAndNegative` (→ `"0:00"`).
- [ ] **Steps 2–5:** standard cycle with `KIT_TEST DisplayTests`. Commit: `feat(core): display formatting`.

## Wave 1 — API

### Task A1: DTO decoding

**Files:** Modify `Packages/OroroKit/Sources/OroroAPI/Decoders.swift`; create `…/OroroAPI/DTOs.swift`. Test `Tests/OroroAPITests/DecodersTests.swift`.

**Interfaces — Produces:**

```swift
public enum Decoders {
    public static func shows(_ data: Data) throws -> [Title]     // top-level key "shows"
    public static func movies(_ data: Data) throws -> [Title]    // top-level key "movies"
    public static func show(_ data: Data) throws -> ShowDetail
    public static func movie(_ data: Data, now: Date) throws -> MovieDetail
    public static func episode(_ data: Data, showID: Int?, now: Date) throws -> EpisodeDetail
}
```

Decisions: field mapping per the spec's API inventory (`poster_thumb`→`posterURL`, `user_popularity`→`popularity`, unix ints→`Date`, `year`/`number` strings→`Int?`, `airdate` `YYYY-MM-DD`→`Date` in UTC). Every field except `id` and `name` decodes leniently: wrong type or unparseable → nil / empty. List items that lack `id` or `name` are skipped. A response whose top-level shape is wrong throws `APIError.decoding`. `playback` is nil when `url` is missing or not a URL; `fetchedAt = now`. `qualities` are the `versions` keys sorted by numeric value. `subtitleLanguages` keep API order, de-duplicated.

- [ ] **Step 1: Tests** — `decodesShowList` (200 titles, first has name/poster/genres, `kind == .show`), `decodesMovieListWithResolution`, `decodesShowDetailWith19Episodes` (seasons [1,2], episode 1: season 1, number 1, airdate 2025-03-30, `.hd`, 5 qualities… use the fixture's actual values), `decodesMovieDetail` (trailer id present, playback URL host `example.invalid`), `decodesEpisodeDetail`, `missingURLGivesNilPlayback`, `wrongTopLevelShapeThrowsDecoding`, plus Review Focus 1:

```swift
@Test func malformedItemsDegradeNotFail() throws {
    let titles = try Decoders.shows(Fixtures.data("malformed-shows"))
    #expect(titles.count == 2)                       // valid one + the one with bad fields; no-name and bad-id are skipped
    let odd = try #require(titles.first { $0.year == nil })
    #expect(odd.imdbRating == nil); #expect(odd.genres.isEmpty); #expect(!odd.name.isEmpty)
}
```

- [ ] **Steps 2–5:** standard cycle with `KIT_TEST DecodersTests`. Commit: `feat(api): lenient DTO decoding`.

### Task A2: Transport

**Files:** Modify `Packages/OroroKit/Sources/OroroAPI/Transport.swift`. Test `Tests/OroroAPITests/TransportTests.swift`.

**Interfaces — Produces:**

```swift
public enum Endpoint: Sendable, Equatable { case shows, movies, show(Int), movie(Int), episode(Int)
    public var path: String }                                   // "/shows", "/shows/12", "/episodes/5", …
public struct RawResponse: Sendable { public let data: Data; public let etag: String?; public let notModified: Bool }
public struct Transport: Sendable {
    public init(baseURL: URL = URL(string: "https://ororo.tv/api/v2")!, session: URLSession = .shared)
    public func send(_ endpoint: Endpoint, credentials: Credentials, ifNoneMatch: String? = nil,
                     progress: (@Sendable (Double) -> Void)? = nil) async throws -> RawResponse
}
```

Decisions: `Authorization: Basic base64(email:password)` (UTF-8); `If-None-Match` when given; status 304 → `notModified`; 401 → `.unauthorized`; 404 → `.notFound`; other non-2xx → `.server(status:)`; `URLError` of kinds notConnectedToInternet / timedOut / networkConnectionLost / cannotFindHost / cannotConnectToHost → `.offline`. Progress is bytes received / expected (0…1), only reported when the length is known. Tests inject a `URLSession` with a stub `URLProtocol`.

- [ ] **Step 1: Tests** — `buildsURLAndBasicAuthHeader` (email with non-ASCII characters encodes as UTF-8), `sendsIfNoneMatch`, `returnsEtagFromHeader`, `maps304ToNotModified`, `maps401`, `maps404`, `maps500ToServer`, `mapsURLErrorToOffline`, `endpointPaths`.
- [ ] **Steps 2–5:** standard cycle with `KIT_TEST TransportTests`. Commit: `feat(api): URLSession transport with basic auth`.

## Wave 1 — Store

Files under `Packages/OroroKit/Sources/OroroStore/`, tests under `Tests/OroroStoreTests/`. Needs: T3 (uses `FakeAPI`, `Samples`).

### Task ST1: Keychain credentials

**Files:** Modify `KeychainCredentialStore.swift`. Test `KeychainCredentialStoreTests.swift`.

**Interfaces — Produces:** `public final class KeychainCredentialStore: CredentialStoring { public init(service: String = "com.dissimirall.Ororo-Player") }` — one generic-password item, account = email, data = password, `kSecAttrAccessibleAfterFirstUnlock`. `save` replaces any existing item.

- [ ] **Step 1: Tests** (each uses a unique `service` and clears it afterwards) — `saveThenLoad`, `saveReplacesPrevious`, `clearRemoves`, `loadWithNothingStoredIsNil`, `clearWhenEmptyDoesNotThrow`.
- [ ] **Steps 2–5:** standard cycle with `KIT_TEST KeychainCredentialStoreTests`. Commit: `feat(store): keychain credential store`.

### Task ST2: Library store

**Files:** Modify `LibraryStore.swift`; create `LibraryPersistence.swift`. Test `LibraryStoreTests.swift`.

**Interfaces — Produces:**

```swift
public protocol LibraryPersistence: Sendable { func read() -> Data?; func write(_ data: Data); func writeBackup(_ data: Data); func remove() }
public struct UserDefaultsLibraryPersistence: LibraryPersistence { public init(defaults: sending UserDefaults = .standard, key: String = "library.v1") }   // backup key: key + ".unreadable"
public struct FileLibraryPersistence: LibraryPersistence { public init(directory: URL) }      // library.json, atomic write
public actor LibraryStore: LibraryStoring {
    public init(persistence: any LibraryPersistence, flushInterval: Duration = .seconds(10), clock: any Clock<Duration> = ContinuousClock())
    public static func platformDefault() -> LibraryStore        // UserDefaults on tvOS, Application Support file elsewhere
    public static let sizeBudget = 300_000
}
```

Decisions: `update` applies the closure, calls `prune()`, publishes to `updates()` streams, and schedules a flush no sooner than `flushInterval` after the previous one; `flush()` writes immediately. `erase()` resets to `Library()` (keeping nothing) and writes. Encoding uses sorted keys and seconds-since-1970 dates.

- [ ] **Step 1: Tests** — `startsEmptyWithNoData`, `updateIsVisibleImmediatelyInSnapshot`, `flushPersistsAndNewStoreReadsItBack`, `writesAreThrottledToFlushInterval` (two updates within the interval → one write; use a test clock), `updatesStreamEmitsEachChange`, `eraseClearsMemoryAndDisk`, `libraryAtAllCapsFitsBudget` (500 list items + 200 progress + 5,000 watched + 200 followed encodes under 300,000 bytes), `updatePrunesBeyondCaps`, plus Review Focus 2:

```swift
@Test func corruptDataStartsEmptyAndIsBackedUp() async {
    let p = InMemoryPersistence(data: Data("not json".utf8))
    let store = LibraryStore(persistence: p)
    #expect(await store.snapshot() == Library())
    #expect(p.backup == Data("not json".utf8))
}
@Test func newerSchemaIsNotOverwritten() async {
    let p = InMemoryPersistence(data: Data(#"{"schemaVersion":99,"futureField":true}"#.utf8))
    let store = LibraryStore(persistence: p)
    #expect(await store.snapshot() == Library())
    await store.update { $0.preferences.autoplayNext = false }; await store.flush()
    #expect(p.backup != nil)                         // the v99 blob survives under the backup key
}
```

(`InMemoryPersistence` is a test-local class in this test file.)

- [ ] **Steps 2–5:** standard cycle with `KIT_TEST LibraryStoreTests`. Commit: `feat(store): durable library store`.

### Task ST3: Catalog repository

**Files:** Modify `CatalogRepository.swift`. Test `CatalogRepositoryTests.swift`.

**Interfaces — Produces:**

```swift
public actor CatalogRepository: CatalogProviding {
    public init(api: any OroroAPI, credentials: any CredentialStoring, directory: URL,
                decodeShows: @escaping @Sendable (Data) throws -> [Title] = Decoders.shows,
                decodeMovies: @escaping @Sendable (Data) throws -> [Title] = Decoders.movies,
                useETag: Bool = true)
    public static let staleness: TimeInterval = 6 * 3600
    public static func cachesDirectory() -> URL          // <Caches>/catalog
}
```

Decisions: files in `directory`: `shows.json`, `movies.json` (raw API bytes), `meta.json` (`fetchedAt`, etags), `home-snapshot.json`. `signIn` fetches shows first (a 401 here throws `.unauthorized` and stores nothing), then movies, writes files, saves credentials, sets `current`. `loadCached` decodes off the caller's actor and returns nil if either file is missing or undecodable. `refresh(force:now:)` returns false without network when not forced and `now - fetchedAt < staleness`; otherwise fetches both with stored etags (when `useETag`), treats `.notModified` as "keep that list", swaps atomically, and returns true only if at least one list changed. A failed refresh throws and leaves the current catalog and files untouched. Progress for `signIn` is the mean of the two downloads. `clear` deletes the directory and forgets `current`. Tests pass decoders that return `Samples` titles, so this task does not need A1.

- [ ] **Step 1: Tests** — `signInFetchesBothCachesAndSavesCredentials`, `signInWith401ThrowsAndSavesNothing`, `loadCachedReadsWhatSignInWrote`, `loadCachedIsNilWithoutFiles`, `refreshSkipsWhenFresh` (zero API calls), `refreshFetchesWhenStale`, `forceRefreshIgnoresFreshness`, `refreshSendsStoredEtagsAndKeepsListOn304`, `refreshWithBoth304ReturnsFalseButUpdatesFetchedAt`, `failedRefreshKeepsOldCatalog`, `homeSnapshotRoundTrips`, `clearRemovesEverything`, `useETagFalseNeverSendsIfNoneMatch`.
- [ ] **Steps 2–5:** standard cycle with `KIT_TEST CatalogRepositoryTests`. Commit: `feat(store): catalog repository with cache and refresh`.

### Task ST4: Detail repository

**Files:** Modify `DetailRepository.swift`. Test `DetailRepositoryTests.swift`.

**Interfaces — Produces:** `public actor DetailRepository: DetailProviding { public init(api: any OroroAPI, credentials: any CredentialStoring, ttl: TimeInterval = 600, now: @escaping @Sendable () -> Date = Date.init) }`.

Decisions: `show`/`movie`/`episode` cache for `ttl`; cached movie and episode values have `playback == nil`. `moviePlayback`/`episodePlayback` always hit the network, return the value with playback, and refresh the stripped cache entry. Concurrent identical requests share one network call. No stored credentials → `APIError.unauthorized`. Nothing is written to disk.

- [ ] **Step 1: Tests** — `showIsCachedWithinTTL` (one API call for two reads), `cacheExpiresAfterTTL`, `cachedMovieHasNoPlayback`, `playbackCallsAlwaysHitNetwork`, `playbackCallRefreshesStrippedCache`, `concurrentRequestsShareOneCall`, `noCredentialsThrowsUnauthorized`, `errorsAreNotCached`, `clearEmptiesCache`.
- [ ] **Steps 2–5:** standard cycle with `KIT_TEST DetailRepositoryTests`. Commit: `feat(store): in-memory detail repository`.

### Task ST5: New-episode resolver

**Files:** Modify `NewEpisodeResolver.swift`. Test `NewEpisodeResolverTests.swift`.

**Interfaces — Produces:** `public actor NewEpisodeResolver: NewEpisodeResolving { public init(details: any DetailProviding, maxPerRun: Int = 10) }`.

Decisions: `resolve` takes the shows to resolve (newest first), fetches `details.show(id:)` one at a time for at most `maxPerRun`, and for each computes the unwatched episodes after the user's last watched episode of that show: last watched = the latest episode in play order whose id is in `library.watchedEpisodes` or in `library.progress`; none watched → no entry. Episodes with nil `number` or in season 0 are ignored. Result `first` = first such episode, `count` = how many. A show with zero unwatched episodes gets no entry. Fetch errors skip that show. Results merge into the cache returned by `cached()`; entries for shows not in the latest `shows` argument are dropped. This task implements the ordering it needs locally (≈10 lines) so it does not depend on C4.

- [ ] **Step 1: Tests** — `resolvesFirstUnwatchedAndCount` (watched S1E1–E3 of 5 → first E4, count 2), `caughtUpShowHasNoEntry`, `neverStartedShowHasNoEntry`, `stopsAtMaxPerRun` (12 shows → 10 detail calls), `fetchesSequentially` (max concurrent calls observed on `FakeDetails` == 1), `failedFetchSkipsThatShow`, `cachedReturnsLastResults`, `staleEntriesAreDropped`.
- [ ] **Steps 2–5:** standard cycle with `KIT_TEST NewEpisodeResolverTests`. Commit: `feat(store): new-episode resolver`.

## Wave 1 — Design

Files under `Packages/OroroUI/Sources/OroroDesign/`, tests under `Packages/OroroUI/Tests/OroroDesignTests/`. Needs: T3. Every view gets a `#Preview` with fake data. View tasks verify by running the preview on tvOS and iOS canvases in addition to tests.

### Task D1: Tokens and motion

**Files:** Modify `Tokens/Motion.swift`, `Tokens/Tokens.swift`. Test `MotionTests.swift`.

**Interfaces — Produces:**

```swift
public enum Motion {
    public static let quick: Animation        // .easeOut(duration: 0.2)
    public static let standard: Animation     // .spring(duration: 0.45, bounce: 0.15)
    public static let cinematic: Animation    // .easeInOut(duration: 0.6)
    public static let staggerStep: Double = 0.04, staggerMax = 5
    public static func staggerDelay(index: Int) -> Double                    // min(index, 5) * 0.04
    public static func resolved(_ token: Animation, reduceMotion: Bool) -> Animation   // reduceMotion → quick
}
public extension View {
    func motion<V: Equatable>(_ token: Animation, value: V) -> some View     // reads accessibilityReduceMotion
    func staggeredAppearance(index: Int) -> some View                        // fade + 24 pt rise; fade only with Reduce Motion
}
public enum Spacing { public static let xs, s, m, l, xl: CGFloat; public static let screenEdge: CGFloat; public static let shelfGap: CGFloat }
public enum Typography { public static let heroTitle, title, headline, body, caption, badge: Font }   // system text styles only
public enum Palette { public static let imdb: Color /* #F5C518 */; public static let scrim, textPrimary, textSecondary, focusHighlight: Color }
```

Values for spacing/typography are the builder's, within the mockups in `.superpowers/brainstorm/…/content/`; tvOS and iOS values may differ via `#if os(tvOS)`.

- [ ] **Step 1: Tests** — `staggerDelayCapsAtFive` (index 0 → 0, 3 → 0.12, 50 → 0.2), `reduceMotionResolvesToQuick`.
- [ ] **Steps 2–5:** standard cycle with `UI_TEST MotionTests`. Commit: `feat(design): tokens and motion system`.

### Task D2: Images and backdrop

**Files:** Modify `Images/RemoteImage.swift`, `Images/BackdropView.swift`, `Images/ImageCache.swift`. Test `ImageCacheTests.swift`.

**Interfaces — Produces:**

```swift
public enum ImageCache {
    public static let diskLimit = 500 * 1024 * 1024
    public static func configure()                                   // builds the shared Nuke pipeline: disk cache "ororo.images", decompression off-main
    public static func request(_ url: URL, pointSize: CGSize, scale: CGFloat) -> ImageRequest   // resize processor to pixel size
    public static func prefetch(_ urls: [URL], pointSize: CGSize)
    public static func preload(_ url: URL, pointSize: CGSize) async  // returns when cached or failed
    public static func clear() async
    public static func diskUsage() async -> Int
}
public struct RemoteImage: View { public init(url: URL?, pointSize: CGSize, contentMode: ContentMode = .fill) }   // fades in with Motion.quick; neutral placeholder
public enum BackdropDim: Sendable { case hero, detail, detailLight }
public struct BackdropView: View { public init(url: URL?, dim: BackdropDim, drift: Bool = false) }   // crossfades on url change (cinematic); drift = 1.00→1.06 over 8 s, off with Reduce Motion
public struct PlaceholderArtwork: View { public init(posterURL: URL?, title: String) }               // blurred poster fill + title text
```

- [ ] **Step 1: Tests** — `requestResizesToPixelSize` (pointSize 300×450 at scale 2 → processor target 600×900), `clearEmptiesDiskUsage`.
- [ ] **Steps 2–5:** standard cycle with `UI_TEST ImageCacheTests`; check previews. Commit: `feat(design): image pipeline and backdrop`.

### Task D3: Controls

**Files:** Modify `Controls/Badge.swift`, `Controls/MetadataLine.swift`, `Controls/ActionButton.swift`, `Controls/Chip.swift`, `Controls/GlassStyle.swift`. Test `ControlsTests.swift`.

**Interfaces — Produces:**

```swift
public struct Badge: View { public init(_ kind: BadgeKind) }
public extension BadgeKind { var accessibilityLabel: String }        // "IMDb rating 8.3", "High definition", "Standard definition", "Subtitles available", "New"
public enum MetadataItem: Hashable, Sendable { case badge(BadgeKind), text(String) }
public struct MetadataLine: View { public init(_ items: [MetadataItem]) }      // one line, " · " between text items, one combined accessibility element
public struct ActionButton: View {
    public enum Style: Sendable { case prominent, regular }
    public init(_ title: String, systemImage: String? = nil, style: Style = .regular, isLoading: Bool = false, action: @escaping () -> Void)
}                                                                              // isLoading: label morphs to a spinner in place, button disabled
public struct Chip: View { public init(_ title: String, isSelected: Bool, action: @escaping () -> Void) }
public struct ToggleListButton: View { public init(isInList: Bool, action: @escaping () -> Void) }   // symbol replace + bounce
public extension View { func glassControl(prominent: Bool = false) -> some View }                   // the S7 seam: glass button/capsule style
```

Badges are solid fills (IMDb yellow with black text; others outlined), never glass.

- [ ] **Step 1: Tests** — `badgeAccessibilityLabels` (all six kinds), `metadataLineAccessibilityLabelJoinsItems` (expose a `static func accessibilityLabel(for: [MetadataItem]) -> String`: `[.badge(.imdb(8.3)), .text("2025"), .badge(.hd)]` → `"IMDb rating 8.3, 2025, High definition"`).
- [ ] **Steps 2–5:** standard cycle with `UI_TEST ControlsTests`; check previews. Commit: `feat(design): badges, buttons and chips`.

### Task D4: Tiles

**Files:** Modify `Tiles/Tiles.swift`. Test `TilesTests.swift`.

**Interfaces — Produces:**

```swift
public struct PosterTile: View { public init(_ model: TileModel, isFocused: Bool) }       // 2:3
public struct LandscapeTile: View { public init(_ model: TileModel, isFocused: Bool) }    // 16:9; title + subtitle reveal below on focus (quick); progress bar; badge top-leading
public struct SeeAllTile: View { public init(shape: TileShape) }
public struct SkeletonTile: View { public init(shape: TileShape) }                        // shimmer; static with Reduce Motion
public enum TileMetrics { public static func size(_ shape: TileShape) -> CGSize }         // per platform
```

Tiles do not own focus or buttons (`ShelfRow`/`PosterGrid` wrap them); a landscape tile with nil `backdropURL` shows `PlaceholderArtwork`. Each tile is one accessibility element using `model.accessibilityLabel`.

- [ ] **Step 1: Tests** — `metricsKeepAspectRatios` (poster 2:3, landscape 16:9 within 0.01).
- [ ] **Steps 2–5:** standard cycle with `UI_TEST TilesTests`; previews show focused/unfocused, with progress, with badge, without backdrop. Commit: `feat(design): poster, landscape and skeleton tiles`.

### Task D5: Shelves, grid, focus memory, detail transition

**Files:** Modify `Shelves/FocusMemory.swift`, `Shelves/ShelfRow.swift`, `Shelves/PosterGrid.swift`, `Transitions/DetailTransition.swift`. Test `FocusMemoryTests.swift`.

**Interfaces — Produces:**

```swift
@MainActor @Observable public final class FocusMemory {
    public init()
    public func remember(_ id: FocusID)
    public func last(screen: String) -> FocusID?
    public func item(screen: String, shelf: String) -> String?
    public func index(screen: String, shelf: String) -> Int?                       // index of the remembered item when stored
    public func resolve(screen: String, shelf: String, available: [String]) -> String?   // remembered id if present; else same index clamped; else first; nil if empty
    public func verticalAnchor(screen: String) -> String?                          // shelf id to restore vertical scroll to
    public func reset(screen: String)
}
public struct ShelfRow: View {
    public init(screen: String, shelf: String, title: String, count: Int? = nil, items: [TileModel], shape: TileShape,
                memory: FocusMemory, zoomNamespace: Namespace.ID? = nil, showsSeeAll: Bool = false, onSeeAll: (() -> Void)? = nil,
                onSelect: @escaping (TileModel) -> Void, menu: @escaping (TileModel) -> AnyView = { _ in AnyView(EmptyView()) })
}
public struct PosterGrid: View {
    public init(screen: String, items: [TileModel], columns: Int = 8, memory: FocusMemory, zoomNamespace: Namespace.ID? = nil,
                onFocusChange: @escaping (TileModel?) -> Void, onSelect: @escaping (TileModel) -> Void,
                menu: @escaping (TileModel) -> AnyView = { _ in AnyView(EmptyView()) })
}
public extension View {
    func detailZoomSource(id: String, in namespace: Namespace.ID?) -> some View     // S2 seam
    func detailZoomDestination(id: String, in namespace: Namespace.ID?) -> some View
}
```

Decisions: `ShelfRow` is a header + horizontal lazy row of `.buttonStyle(.card)` buttons inside `.focusSection()`. It keeps its own `ScrollPosition` keyed by item id and its own `@FocusState`; on appear it scrolls to `memory.resolve(…)` and uses it as `defaultFocus`; on focus change it calls `memory.remember`. Zoom source id is `"<shelf>/<item>"` so the same title in two shelves differs. It prefetches images for the next 6 items. `PosterGrid` is a `LazyVGrid` with the same memory behaviour (shelf id `"grid"`). Zoom modifiers use `matchedTransitionSource` / `.navigationTransition(.zoom)`; with a nil namespace or Reduce Motion they do nothing (default push becomes a crossfade).

- [ ] **Step 1: Tests**

```swift
@Test @MainActor func remembersPerShelfAndScreen() {
    let m = FocusMemory(); m.remember(FocusID(screen: "home", shelf: "popular", item: "show-3"))
    #expect(m.item(screen: "home", shelf: "popular") == "show-3"); #expect(m.last(screen: "home")?.shelf == "popular")
    #expect(m.item(screen: "shows", shelf: "popular") == nil)
}
@Test @MainActor func resolveFallsBackToSameIndexThenFirst() {
    let m = FocusMemory(); let ids = ["a", "b", "c", "d"]
    _ = m.resolve(screen: "s", shelf: "x", available: ids); m.remember(FocusID(screen: "s", shelf: "x", item: "c"))
    #expect(m.resolve(screen: "s", shelf: "x", available: ids) == "c")
    #expect(m.resolve(screen: "s", shelf: "x", available: ["a", "b", "z", "d"]) == "z")   // c gone → index 2
    #expect(m.resolve(screen: "s", shelf: "x", available: ["a"]) == "a")                   // clamped
    #expect(m.resolve(screen: "s", shelf: "x", available: []) == nil)
}
@Test @MainActor func resetForgetsOnlyThatScreen()
```

(For the index fallback `remember` must know the index: `ShelfRow` calls `resolve` with the current ids before `remember`, and `FocusMemory` records the index from the last `available` list it saw.)

- [ ] **Steps 2–4:** standard cycle with `UI_TEST FocusMemoryTests`.
- [ ] **Step 5:** Manual check in the tvOS simulator with a preview of 8 shelves × 30 tiles: move to the 20th tile of shelf 4, push a dummy destination, go back → focus returns to the same tile. Commit: `feat(design): shelves, grid and focus memory`.

---

## Wave 1 — Spikes (owner + Apple TV 4K; throwaway code)

All spikes: branch `spike/phase0` (never merged), code under `Spikes/<Sn>/` as a small standalone tvOS app using the T2 fixtures (real artwork URLs). Measure with Instruments → Animation Hitches, release build. Each ends by appending a row to a new "Spike results" section in the spec: result, numbers, decision (primary kept / fallback `X-Sn` needed), then committing the spec change to `redesign/tvos-swiftui`. Pass criteria are the spec's Phase 0 table, repeated here.

| Task | Build | Pass |
|---|---|---|
| **S1** focus memory | 8 lazy shelves × 30 tiles in a `TabView` + `NavigationStack`, SwiftUI only | tile → detail → Menu returns to the same tile 20/20 incl. tiles scrolled far right; tab switch and back likewise |
| **S2** zoom transition | landscape tile → full-screen detail with `.navigationTransition(.zoom)` | hitch ratio < 5 ms/s on push and pop |
| **S3** hero | full-screen hero with 2 buttons, paging past the outer button, focus-driven collapse | < 5 ms/s; paging never steals or loses button focus |
| **S4** subtitles | `AVAssetResourceLoaderDelegate` serving the synthetic master (hand-built), real signed stream from a signed-in session | cues within ±100 ms at start, mid-stream, after seek, on 3 titles incl. Russian; native subtitle menu lists the languages |
| **S5** grid | `LazyVGrid`, 8 columns, 7,920 posters | < 5 ms/s during continuous traversal |
| **S6** trailer | `canOpenURL` + `open` for `youtube://watch/n9xhJrPXop4` | YouTube opens that video |
| **S7** glass | glass buttons and capsules over a moving backdrop | < 5 ms/s |
| **S8** durability, ETag | write a `UserDefaults` blob, reinstall over the top, fill the device to force a cache purge; `curl -I` the list endpoints twice with `If-None-Match` | blob survives both; server returns 304 |

- [ ] One checkbox per spike: build → measure → record result in the spec → commit.

---

## Wave 2 — Features

Files under `Packages/OroroUI/Sources/OroroFeatures/<Feature>/`, tests under `Packages/OroroUI/Tests/OroroFeaturesTests/`. All view-model tests use the `OroroTestSupport` fakes and `Samples`. Each task finishes with a manual pass in the tvOS simulator and `UI_BUILD_IOS`. Loading / empty / error states follow the spec's *States and errors* table.

### Task F1: App root, session, navigation

**Needs:** ST1–ST3, ST5, D5. **Files:** Modify `AppRoot/AppRootView.swift`, `AppRoot/AppSession.swift`; create `AppRoot/TabRootView.swift`, `AppRoot/RouteDestination.swift`, `AppRoot/LoadingScreen.swift`, `AppRoot/ReauthSheet.swift`. Test `AppSessionTests.swift`.

**Interfaces — Produces:**

```swift
@MainActor @Observable public final class AppSession {
    public enum State: Equatable { case launching, signedOut, loadingCatalog(Double), ready, failed(APIError) }
    public private(set) var state: State
    public private(set) var catalog: Catalog?            // nil while only the Home snapshot is available
    public private(set) var catalogVersion: Int          // bumps when a new catalog is swapped in
    public private(set) var newEpisodeInfo: [Int: NewEpisodeInfo]
    public var needsReauth: Bool
    public init(environment: AppEnvironment)
    public func start() async                            // credentials? → loadCached → ready; then refresh in background
    public func signIn(email: String, password: String) async throws
    public func signOut() async                          // clears credentials, details, catalog cache; library untouched
    public func refresh(force: Bool) async
    public func sceneBecameActive() async                // refresh if stale
    public func report(_ error: any Error)               // .unauthorized → needsReauth = true
    public func retry() async
}
```

Decisions: `start` with credentials and a cache → `.ready` at once and `refresh(force: false)` in the background; credentials but no cache → `.loadingCatalog` via `catalog.signIn`; no credentials → `.signedOut`. After each successful refresh, run `newEpisodes.resolve` for `LibraryQueries.showsWithNewEpisodes` and publish `newEpisodeInfo`. `AppRootView` switches on `state` (SignIn / LoadingScreen with byte progress / tabs / full-screen error with Retry), owns one `TabRouter` per tab and the `PlaybackLauncher`, presents `PlayerScreen` in `fullScreenCover(item: $launcher.active)`, shows `ReauthSheet` when `needsReauth`, and flushes the library on `scenePhase == .background`. `TabRootView` is the `TabView` in the spec's order with Settings as a gear-only trailing tab; each tab is `NavigationStack(path:)` with `RouteDestination` mapping `Route` → `DetailScreen` / `BrowseGridScreen`. Menu behaviour per the spec's table: at a tab root with `router.isAtTop == false`, `onExitCommand` increments `router.scrollToTopToken`; otherwise system default. F1 also provides the `selectTab` environment action. (Root screens F2, F4, F7, F8 maintain `isAtTop` and react to the token.)

- [ ] **Step 1: Tests** — `startWithoutCredentialsIsSignedOut`, `startWithCacheIsReadyImmediatelyThenRefreshes`, `startWithCredentialsButNoCacheLoads`, `signInSuccessBecomesReady`, `signInWrongPasswordThrowsUnauthorizedAndStaysSignedOut`, `signInOfflineThrowsOffline`, `signOutClearsCredentialsButKeepsLibrary`, `reportUnauthorizedSetsNeedsReauth`, `reportOtherErrorDoesNot`, `refreshBumpsCatalogVersionOnlyWhenChanged`, `refreshResolvesNewEpisodes`, `failedBackgroundRefreshKeepsReady`.
- [ ] **Steps 2–5:** standard cycle with `UI_TEST AppSessionTests`. Commit: `feat(app): session, tabs and routing`.

### Task F2: Home screen

**Needs:** C1, C5, D4, D5. **Files:** Modify `Home/HomeScreen.swift`; create `Home/HomeViewModel.swift`. Test `HomeViewModelTests.swift`.

**Interfaces — Produces:**

```swift
@MainActor @Observable final class HomeViewModel {
    private(set) var content: HomeContent?               // nil → skeleton shelves
    init(environment: AppEnvironment)
    func appear(catalog: Catalog?, newEpisodeInfo: [Int: NewEpisodeInfo]) async   // rebuilds only here, never while visible
    func libraryChanged(_ library: Library)              // updates personal rows + hero actions only
    func select(_ item: ShelfItem, shelf: Shelf, router: TabRouter, launcher: PlaybackLauncher)
    func heroPlay(_ item: HeroItem, launcher: PlaybackLauncher)
    func toggleList(_ title: Title) async
}
```

Decisions: on first appear with no catalog, show `catalog.homeSnapshot()`; once a catalog exists build with `ShelfBuilder` + `LibraryQueries`, then `saveHomeSnapshot`. A new `catalogVersion` is applied on the next `appear`, not while visible. Select: item with `playable` → `launcher.play`; otherwise `router.open(title.id)`. Hero play maps `HeroAction` to `PlayRequest.Target` (`.playFirstEpisode` → `.show(id)`). The screen is `HeroView` + a vertical lazy stack of `ShelfRow`s (landscape), screen id `"home"`, `isExpanded` = focus is inside the hero; shelves use `staggeredAppearance`. Passes a zoom namespace to rows.

- [ ] **Step 1: Tests** — `showsSnapshotBeforeCatalog`, `buildsFromCatalogAndSavesSnapshot`, `personalRowsHiddenWhenEmpty`, `libraryChangeUpdatesContinueWatchingWithoutReorderingCatalogRows`, `newCatalogAppliedOnlyOnNextAppear`, `selectPlayableItemPlays`, `selectPlainItemOpensDetail`, `heroPlayFirstEpisodeTargetsShow`, `toggleListUpdatesLibrary`.
- [ ] **Steps 2–5:** standard cycle with `UI_TEST HomeViewModelTests`. Commit: `feat(home): home screen and view model`.

### Task F3: Hero

**Needs:** D1–D3. **Files:** Modify `Home/HeroView.swift`; create `Home/HeroPager.swift`. Test `HeroPagerTests.swift`.

**Interfaces — Produces:**

```swift
public struct HeroView: View {
    public init(items: [HeroItem], isExpanded: Bool, isInList: @escaping (Title) -> Bool,
                onPlay: @escaping (HeroItem) -> Void, onToggleList: @escaping (Title) -> Void)
}
struct HeroPager: Equatable {                              // pure state machine
    static let dwell: TimeInterval = 8
    private(set) var index = 0
    init(count: Int)
    mutating func next(); mutating func previous()       // wrap around
    mutating func userInteracted(at time: TimeInterval)
    mutating func tick(at time: TimeInterval, focusInHero: Bool, sceneActive: Bool, reduceMotion: Bool) -> Bool   // true when it advanced
}
```

Decisions: auto-advance when `focusInHero && sceneActive && !reduceMotion` and at least 8 s since both the last interaction and the last advance. Buttons: Play/Resume label from `HeroAction` (`"Play"`, `"Play S1 E1"`, `"Resume S2 E3"`), then `ToggleListButton`. `onMoveCommand`: right on the last button → `next()`, left on the first → `previous()`; both count as interaction. Content per spec (no CC badge). Paging animates per the choreography table (`cinematic` crossfade via `BackdropView(drift: true)`, text fades and slides). Collapse: one `Motion.standard` animation on `isExpanded` changing height, scale and dim; no geometry-driven state. Page dots are decorative and hidden from VoiceOver; the hero announces "n of 6".

- [ ] **Step 1: Tests** — `advancesAfterDwellWhenIdleAndFocused`, `doesNotAdvanceBeforeDwell`, `interactionResetsDwell`, `noAdvanceWhenFocusOutsideHero`, `noAdvanceWhenSceneInactive`, `noAdvanceWithReduceMotion`, `nextAndPreviousWrap`, `singleItemNeverAdvances`, `zeroItemsIsSafe`.
- [ ] **Steps 2–5:** standard cycle with `UI_TEST HeroPagerTests`; manual check of paging and collapse in the simulator. Commit: `feat(home): hero with paging and collapse`.

### Task F4: Shows / Movies tab

**Needs:** C1, D4, D5. **Files:** Modify `Browse/BrowseTabScreen.swift`; create `Browse/BrowseTabViewModel.swift`. Test `BrowseTabViewModelTests.swift`.

**Interfaces — Produces:** `@MainActor @Observable final class BrowseTabViewModel { private(set) var shelves: [Shelf]?; init(kind: TitleKind); func appear(catalog: Catalog?, version: Int); func seeAll(_ shelf: Shelf, router: TabRouter); func browseAll(router: TabRouter); func select(_ item: ShelfItem, router: TabRouter) }`

Decisions: rebuild only when `version` differs from the one last built, and only in `appear`. Poster `ShelfRow`s with `count: shelf.totalCount`, `showsSeeAll: true`; See All pushes `.browse(shelf.seeAll!)`; **Browse All** button pushes `.browse(.default(kind))`. Screen id `"shows"` / `"movies"`. Skeleton shelves while `shelves == nil`.

- [ ] **Step 1: Tests** — `nilCatalogGivesSkeleton`, `buildsShelvesForKind`, `doesNotRebuildForSameVersion`, `rebuildsForNewVersionOnAppear`, `seeAllPushesPresetQuery`, `browseAllPushesDefaultQuery`, `selectOpensDetail`.
- [ ] **Steps 2–5:** standard cycle with `UI_TEST BrowseTabViewModelTests`. Commit: `feat(browse): shows and movies shelves`.

### Task F5: Filter grid

**Needs:** C2, D3–D5. **Files:** Modify `Browse/BrowseGridScreen.swift`; create `Browse/BrowseGridViewModel.swift`, `Browse/FilterBar.swift`. Test `BrowseGridViewModelTests.swift`.

**Interfaces — Produces:** `@MainActor @Observable final class BrowseGridViewModel { var query: BrowseQuery; private(set) var results: [Title]; private(set) var isFiltering: Bool; private(set) var focused: Title?; let genres: [String]; let decades: [Int]; init(query: BrowseQuery, catalog: Catalog); func setGenre(_:), setDecade(_:), setMinRating(_:), setStatus(_:), setSort(_:); func reset(); func focusChanged(_ id: String?); var availableSorts: [BrowseQuery.Sort]; var showsStatusFilter: Bool; var footerText: String? }`

Decisions: every setter mutates `query`, then recomputes `results` off the main actor (cancelling an in-flight computation). `availableSorts` omits `.popular` for movies; `showsStatusFilter` is false for movies. `reset()` returns to `.default(kind)`. `footerText` = "name · IMDb x · year · Ongoing/Ended", updated with a 150 ms debounce and `Motion.quick` crossfade. Query changes are written back into the router's path entry so Back/tab switches keep them. Changing a filter crossfades the whole grid and resets `FocusMemory` for the grid. Empty results → "No titles match" + **Reset Filters**. Header shows the result count. Min IMDb options: Any, 6+, 7+, 8+.

- [ ] **Step 1: Tests** — `initialResultsMatchQuery`, `settersUpdateResults`, `movieQueryHidesPopularSortAndStatus`, `resetRestoresDefault`, `rapidChangesKeepOnlyLastResult`, `footerTextForShowAndMovie`, `emptyResultIsReported`.
- [ ] **Steps 2–5:** standard cycle with `UI_TEST BrowseGridViewModelTests`. Commit: `feat(browse): filter grid`.

### Task F6: Detail

**Needs:** C4, C5, C7, ST4, D2–D5. **Files:** Modify `Detail/DetailScreen.swift`; create `Detail/DetailViewModel.swift`, `Detail/DetailInfoColumn.swift`, `Detail/EpisodeList.swift`, `Detail/EpisodeRow.swift`, `Detail/SubtitleLanguagePicker.swift`, `Detail/TrailerAvailability.swift`. Test `DetailViewModelTests.swift`.

**Interfaces — Produces:**

```swift
@MainActor @Observable final class DetailViewModel {
    enum Load: Equatable { case loading, loaded, failed }
    let id: TitleID
    private(set) var title: Title?                      // from catalog immediately
    private(set) var load: Load
    private(set) var seasons: [Int], selectedSeason: Int?, episodes: [Episode]      // of the selected season
    private(set) var resume: EpisodeRef?                // in-progress, else up-next
    private(set) var subtitleLanguages: [String]?, qualityText: String?, trailerID: String?
    private(set) var isInList: Bool, preferredSubtitle: String?
    var metadata: [MetadataItem] { get }
    var primaryButtonTitle: String { get }              // "Play", "Resume", "Play S1 E1", "Resume S2 E3"
    init(id: TitleID, catalog: Catalog?, environment: AppEnvironment, session: AppSession)
    func appear() async; func retry() async
    func selectSeason(_ season: Int)
    func playPrimary(launcher: PlaybackLauncher); func play(_ episode: Episode, startOver: Bool, launcher: PlaybackLauncher)
    func toggleList() async; func setPreferredSubtitle(_ lang: String?) async
    func setWatched(_ episode: Episode, _ watched: Bool) async
    func fraction(_ episode: Episode) -> Double?; func isWatched(_ episode: Episode) -> Bool
    func returnedFromPlayer(lastPlayed: PlayableID?) -> Int?     // episode id to focus; switches season if needed
}
enum TrailerAvailability { @MainActor static func url(for youTubeID: String) -> URL? }   // S6 seam: tvOS youtube:// if canOpenURL else nil; iOS falls back to https://youtube.com/watch?v=
```

Decisions: `appear` loads `details.show` or `details.movie`; for shows it then prefetches `details.episode` of the resume/first episode to fill `subtitleLanguages`; quality text from `EpisodeOrdering.qualityRange` (shows) or movie `qualities`. Errors go to `session.report` and set `.failed` (inline Retry in the right column; left column stays usable). Metadata per spec, HD for shows only when any episode is HD. Layout, focus rules (start on primary button; right → resume episode else first row, later the last focused row; left → last focused button), skeleton rows, expanding focused row, season slide, long-press menu (Play from Beginning, Mark as Watched/Unwatched) all per the spec's Detail section and choreography table. Backdrop is preloaded (`ImageCache.preload`) and the view uses `detailZoomDestination`. Unnamed episode → "Episode N". Zero episodes → "No episodes yet". iOS: stacked layout.

- [ ] **Step 1: Tests** — `showsCatalogDataBeforeNetwork`, `loadsShowSeasonsAndSelectsResumeSeason`, `selectsFirstSeasonWithoutProgress`, `selectSeasonFiltersEpisodes`, `primaryButtonTitleForEachState` (movie fresh/in progress, show fresh/in progress/up-next), `playPrimaryTargets` (movie → `.movie`, show → `.show`), `playEpisodeStartOverFlag`, `metadataForMovie` (IMDb, year, runtime, HD), `metadataForShowAddsNewEpisodeAgoWithin14Days`, `subtitleLanguagesComeFromEpisodePrefetch`, `qualityTextFromEpisodes`, `failedLoadReportsAndAllowsRetry`, `unauthorizedIsReportedToSession`, `toggleListAndMarkWatchedUpdateLibrary`, `returnedFromPlayerSwitchesSeason`, `showWithNoEpisodes`.
- [ ] **Steps 2–5:** standard cycle with `UI_TEST DetailViewModelTests`. Commit: `feat(detail): split detail screen`.

### Task F7: Search

**Needs:** C1, C3, D5. **Files:** Modify `Search/SearchScreen.swift`; create `Search/SearchViewModel.swift`. Test `SearchViewModelTests.swift`.

**Interfaces — Produces:** `@MainActor @Observable final class SearchViewModel { var query: String; private(set) var results: SearchResults?; private(set) var suggestions: [Shelf]; init(debounce: Duration = .milliseconds(150)); func setCatalog(_ catalog: Catalog?, version: Int); func queryChanged() async; var showsNoResults: Bool }`

Decisions: the index is built off the main actor once per catalog version. Empty query → `results = nil` and the screen shows `suggestions` (Popular Shows + Top Rated Movies from `ShelfBuilder`). Stale searches are cancelled. `.searchable`; two poster `ShelfRow`s titled Shows / Movies, each hidden when empty; "No results for '<query>'" when both are empty.

- [ ] **Step 1: Tests** — `emptyQueryShowsSuggestions`, `queryProducesResultsAfterDebounce`, `rapidTypingRunsOneSearch`, `staleResultIsDiscarded`, `noResultsFlag`, `newCatalogVersionRebuildsIndex`, `nilCatalogIsSafe`.
- [ ] **Steps 2–5:** standard cycle with `UI_TEST SearchViewModelTests`. Commit: `feat(search): local search`.

### Task F8: My List

**Needs:** C5, D4, D5. **Files:** Modify `MyList/MyListScreen.swift`; create `MyList/MyListViewModel.swift`. Test `MyListViewModelTests.swift`.

**Interfaces — Produces:** `@MainActor @Observable final class MyListViewModel { private(set) var continueWatching: [ShelfItem], newEpisodes: [ShelfItem], titles: [Title]; var isEmpty: Bool; init(environment: AppEnvironment); func update(library: Library, catalog: Catalog?, newEpisodeInfo: [Int: NewEpisodeInfo]); func select(_ item: ShelfItem, router: TabRouter, launcher: PlaybackLauncher) }`

Decisions: two landscape `ShelfRow`s (hidden when empty) then a `PosterGrid` of My List; observes `library.updates()`. Empty state: short explanation + button that calls `@Environment(\.selectTab)` with `.shows`. Screen id `"mylist"`.

- [ ] **Step 1: Tests** — `emptyLibraryIsEmpty`, `rowsReflectLibrary`, `myListNewestFirst`, `updatesWhenLibraryChanges`, `selectPlayableVsOpenDetail`.
- [ ] **Steps 2–5:** standard cycle with `UI_TEST MyListViewModelTests`. Commit: `feat(mylist): my list tab`.

### Task F9: Playback session (logic)

**Needs:** C4, C5, ST4. **Files:** Modify `Player/PlaybackSession.swift`. Test `PlaybackSessionTests.swift` (with a test-local `FakeEngine: PlayerEngine`).

**Interfaces — Produces:**

```swift
@MainActor @Observable public final class PlaybackSession {
    public enum Phase: Equatable { case preparing, askResume(position: TimeInterval), playing, countdown(next: EpisodeRef, secondsLeft: Int),
                                   stillWatching, failed(Failure), finished }
    public enum Failure: Equatable { case fetch, notPlayable, stream }
    public private(set) var phase: Phase
    public private(set) var current: PlayableID?, nextEpisode: Episode?, showsNextEpisodeAction: Bool
    public init(request: PlayRequest, environment: AppEnvironment, session: AppSession, engine: any PlayerEngine,
                clock: any Clock<Duration> = ContinuousClock(), now: @escaping () -> Date = Date.init)
    public func start() async
    public func chooseResume(_ resume: Bool) async
    public func playNextNow() async; public func cancelCountdown()
    public func confirmStillWatching(_ yes: Bool) async
    public func retry() async
    public func willDismiss() async                        // record + flush; sets launcher.lastPlayed via return value
    public func sceneBecameActive() async
}
```

Decisions (spec's Player section, verbatim constants in Global Constraints):
- `start`: resolve `.show(id)` to an episode (library resume target, else `details.show` → first); fetch `…Playback`; nil `playback` → `.failed(.notPlayable)`; fetch error → `.failed(.fetch)` and `session.report`; resume position from `Library.resumePosition` unless `startOver` → `.askResume`, else load and play.
- Engine load gets `library.preferences.subtitleLanguage` only if the title has it, else nil. `.subtitleChanged(lang)` writes the preference.
- `.time` events: record progress in memory every event, via `library.update` at most every 10 s; `showsNextEpisodeAction` when ≤ 40 s remain and a next episode exists; at ≥ 95% call `finish` once.
- `.paused` → update + `flush`. `.ended` → next exists and `autoplayNext` → `.countdown` from 5 (third consecutive autoplay without `.userInput` → `.stillWatching` first); else `.finished`.
- `.failed`, or `.stalled(seconds: ≥ 30)`, or `sceneBecameActive` with `now - playback.fetchedAt > 30 h`: refetch playback, reload at the last position — one automatic attempt per failure, then `.failed(.stream)`.
- Next episode load fetches fresh playback for it and resets `current`.

- [ ] **Step 1: Tests** — `movieStartsPlayingFromZero`, `showTargetResolvesResumeThenUpNextThenFirst`, `asksResumeBetween60sAnd95Percent`, `startOverSkipsPrompt`, `missingURLIsNotPlayable`, `fetchErrorFailsAndReports`, `progressWrittenAtMostEvery10s`, `pauseFlushes`, `marksWatchedOnceAt95Percent`, `nextActionAppearsInLast40s`, `endStartsCountdownThenPlaysNext`, `cancelCountdownFinishes`, `autoplayOffFinishes`, `thirdAutoplayAsksStillWatching`, `userInputResetsAutoplayCount`, `lastEpisodeFinishes`, `streamFailureRefetchesOnceThenFails`, `stallOf30sIsAFailure`, `expiredURLRefetchedOnForeground`, `preferredSubtitleOnlyWhenAvailable`, `changingSubtitleUpdatesPreference`, `zeroDurationNeverMarksWatched`, `willDismissRecordsAndFlushes`.
- [ ] **Steps 2–5:** standard cycle with `UI_TEST PlaybackSessionTests`. Commit: `feat(player): playback session logic`.

### Task F10: Player engine and screen

**Needs:** C6, D1, D3. **Files:** Modify `Player/PlayerScreen.swift`; create `Player/AVPlayerEngine.swift`, `Player/SubtitleProvider.swift`, `Player/SubtitleResourceLoader.swift`, `Player/PlayerContainer.swift` (`UIViewControllerRepresentable` for `AVPlayerViewController`), `Player/PlayerOverlays.swift`. Test `SubtitleResourceLoaderTests.swift`.

**Interfaces — Produces:**

```swift
@MainActor final class AVPlayerEngine: PlayerEngine { init(subtitles: any SubtitleProvider = HLSInjectedSubtitles()); let player: AVPlayer }
@MainActor protocol SubtitleProvider {                                 // the S4 seam
    func makeAsset(for playback: Playback, preferredLanguage: String?) -> AVURLAsset
    func attach(to controller: AVPlayerViewController, engine: AVPlayerEngine)
}
final class HLSInjectedSubtitles: SubtitleProvider                     // custom-scheme asset + SubtitleResourceLoader
struct SubtitleResourceResponder: Sendable {                           // pure core of the loader, unit-tested
    init(playback: Playback, preferredLanguage: String?, fetch: @escaping @Sendable (URL) async throws -> Data)
    func response(for url: URL, duration: TimeInterval) async throws -> (data: Data, contentType: String)
}
```

Decisions: `HLSInjectedSubtitles.makeAsset` returns an asset for `SubtitlePlaylistBuilder.masterURL()` with a resource-loader delegate. The responder answers the master URL (fetch original, `SubtitlePlaylistBuilder.master`) and each subtitle URL (`subtitlePlaylist(vttURL:duration:)`), content type `application/x-mpegURL`; unknown URLs throw. With no subtitles, `makeAsset` returns a plain asset for `playback.streamURL`. `AVPlayerEngine` maps a periodic time observer (1 s), `timeControlStatus`, item status/failed-to-end, end notification and media-selection changes to `PlayerEvent`s; stall seconds counted while `waitingToPlayAtSpecifiedRate`; audio session `.playback`. `PlayerScreen(request:)` creates engine + `PlaybackSession`, hosts `PlayerContainer`, and renders phases: resume alert (**Resume from mm:ss / Start Over**), `contextualActions` "Next Episode" when `showsNextEpisodeAction` (tvOS; an overlay button on iOS), countdown overlay with cancel, "Still watching?" alert, failure alerts with the spec's copy (Retry / Close), and dismisses on `.finished`. On dismissal it calls `willDismiss` and sets `launcher.lastPlayed`. Presented and dismissed through black.

- [ ] **Step 1: Tests** — `masterRequestReturnsRewrittenPlaylistWithSubtitleEntries`, `subtitleRequestReturnsOneSegmentPlaylistForThatLanguage`, `unknownURLThrows`, `masterFetchFailurePropagates`, `contentTypeIsMpegURL`.
- [ ] **Steps 2–4:** standard cycle with `UI_TEST SubtitleResourceLoaderTests`.
- [ ] **Step 5:** Manual check in the tvOS simulator, signed in with real credentials: a movie plays; the native subtitle menu lists its languages and shows cues; resume prompt appears on second launch; Next Episode appears in the last 40 s of an episode. Commit: `feat(player): AVKit engine, native subtitles and player screen`.

### Task F11: Sign-in

**Needs:** D3. **Files:** Modify `SignIn/SignInScreen.swift`; create `SignIn/SignInViewModel.swift`. Test `SignInViewModelTests.swift`.

**Interfaces — Produces:** `@MainActor @Observable final class SignInViewModel { var email: String, password: String; private(set) var isWorking: Bool; private(set) var error: Message?; enum Message: Equatable { case wrongCredentials, offline, server }; var canSubmit: Bool; init(signIn: @escaping (String, String) async throws -> Void); func submit() async }`

Decisions: `canSubmit` requires a non-empty trimmed email containing `@` and a non-empty password; email is trimmed before submit. `.unauthorized` → `.wrongCredentials`; `.offline` → `.offline`; anything else → `.server`. Fields use `.textContentType(.username)` + `.keyboardType(.emailAddress)` + no autocapitalisation, and `.textContentType(.password)` with `SecureField`. Button uses `ActionButton(isLoading:)`. The same view (prefilled email) is reused by F1's `ReauthSheet`.

- [ ] **Step 1: Tests** — `cannotSubmitEmptyOrInvalid`, `trimsEmail`, `successClearsError`, `mapsUnauthorized`, `mapsOffline`, `mapsOtherToServer`, `isWorkingDuringSubmit`, `doubleSubmitRunsOnce`.
- [ ] **Steps 2–5:** standard cycle with `UI_TEST SignInViewModelTests`. Commit: `feat(signin): sign-in screen`.

### Task F12: Settings

**Needs:** C7, D2, D3. **Files:** Modify `Settings/SettingsScreen.swift`; create `Settings/SettingsViewModel.swift`. Test `SettingsViewModelTests.swift`.

**Interfaces — Produces:** `@MainActor @Observable final class SettingsViewModel { private(set) var email: String?, subtitleLanguage: String?, autoplayNext: Bool, lastUpdated: Date?, imageCacheBytes: Int, isRefreshing: Bool; let languages: [String]; let version: String; init(environment: AppEnvironment, session: AppSession, clearImages: @escaping () async -> Void = ImageCache.clear, imageUsage: @escaping () async -> Int = ImageCache.diskUsage); func load() async; func setSubtitleLanguage(_:) async; func setAutoplay(_:) async; func refreshCatalog() async; func clearImageCache() async; func eraseLibrary() async; func signOut() async }`

Decisions: rows per the spec's Settings list. `languages` = `en, ru, es, de, fr, it, pt, pl, tr, cs` plus an Off option (nil), shown with `Display.languageName`. Erase requires a confirmation dialog. Version from the main bundle's short version + build.

- [ ] **Step 1: Tests** — `loadReadsPreferencesAndAccount`, `setSubtitleLanguageIncludingOffPersists`, `setAutoplayPersists`, `refreshCallsForceRefresh`, `clearImageCacheCallsThroughAndReloadsUsage`, `eraseLibraryEmptiesStore`, `signOutCallsSession`.
- [ ] **Steps 2–5:** standard cycle with `UI_TEST SettingsViewModelTests`. Commit: `feat(settings): settings tab`.

### Task F13: Title long-press menu

**Needs:** C5. **Files:** Modify `Shared/TitleMenu.swift`. Test `TitleMenuTests.swift`.

**Interfaces — Produces:**

```swift
public enum MenuContext: Sendable { case plain, continueWatching, newEpisodes }
public enum TitleMenuAction: Hashable, Sendable { case addToList, removeFromList, removeFromContinueWatching, markWatched, dismissNew, goToShow }
enum TitleMenuModel {
    static func actions(for item: ShelfItem, context: MenuContext, library: Library) -> [TitleMenuAction]
    static func perform(_ action: TitleMenuAction, item: ShelfItem, environment: AppEnvironment, router: TabRouter) async
}
@MainActor public func titleMenu(for item: ShelfItem, context: MenuContext, library: Library, environment: AppEnvironment, router: TabRouter) -> AnyView
```

Decisions: `.plain` → add or remove (one of them). `.continueWatching` → that plus Remove from Continue Watching, Mark as Watched, and Go to Show (shows only). `.newEpisodes` → add/remove, Dismiss, Mark as Watched, Go to Show. Mark as Watched on an item with an episode calls `finish` semantics without a next episode lookup: `markWatched` + clear progress; on a movie likewise. Dismiss calls `dismissNewEpisodes(showID:newestVideo:)` with the title's current `newestVideo`. Home, My List, Browse and Search pass this into `ShelfRow`/`PosterGrid`'s `menu:` (those tasks call `titleMenu`; until F13 merges the stub returns `EmptyView`).

- [ ] **Step 1: Tests** — `plainOffersAddOrRemove`, `continueWatchingActionsForMovieAndShow`, `newEpisodesActions`, `performAddAndRemove`, `performRemoveFromContinueWatching`, `performMarkWatched`, `performDismissNew`, `performGoToShowPushesRoute`.
- [ ] **Steps 2–5:** standard cycle with `UI_TEST TitleMenuTests`. Commit: `feat(shared): title context menu`.

---

## Wave 3 — Integration

### Task I1: Localisation

**Needs:** all F tasks. **Files:** Modify `Packages/OroroUI/Sources/OroroFeatures/Resources/Localizable.xcstrings`, `Packages/OroroUI/Sources/OroroDesign/Resources/Localizable.xcstrings` (both created empty by T1); create `Packages/OroroUI/Sources/OroroFeatures/Shared/GenreName.swift`; test `GenreNameTests.swift`, `LocalisationTests.swift`.

**Interfaces — Produces:** `enum GenreName { static func localized(_ apiName: String, locale: Locale = .current) -> String }` — key `genre.<lowercased, spaces→_>`, falling back to the API string. After this task, feature views display genres through it (a mechanical replace of direct genre strings in F2, F4, F5, F6 files — the one permitted cross-file edit, done here after those tasks merged).

- [ ] **Step 1:** Tests: `knownGenreIsTranslatedInRussian` (`"Comedy"` ≠ result for `ru`), `unknownGenreFallsBack`, `everyKeyHasRussian` (parse both `.xcstrings` as JSON; every key has a non-empty `ru` value), `all27FixtureGenresHaveKeys` (genres collected from the `shows` + `movies` fixtures).
- [ ] **Step 2:** Build once so Xcode extracts keys; fill English from `defaultValue` and write Russian for every key and all genres. The 2018 `ru.lproj/Localizable.strings` is the reference for existing terms.
- [ ] **Step 3:** `UI_TEST GenreNameTests`, `UI_TEST LocalisationTests` pass. Run the tvOS app with `-AppleLanguages (ru)` and walk every screen for untranslated or clipped strings.
- [ ] **Step 4:** Commit: `feat: English and Russian localisation`.

### Task I2: App wiring, legacy cleanup, old code removal

**Needs:** all F tasks. **Files:** Create `Packages/OroroKit/Sources/OroroStore/LegacyCleanup.swift`, `Tests/OroroStoreTests/LegacyCleanupTests.swift`; modify `Apps/TV/OroroTVApp.swift`, `Apps/iOS/OroroApp.swift`, `Project.swift` (app icons / Top Shelf image assets moved to `Apps/TV/Assets.xcassets`, iOS icons to `Apps/iOS/Assets.xcassets`), `README.md`, `.github/workflows/ci.yml`; delete `Ororo-Player/`, `Ororo-Kit/`, `Ororo-Player.xcworkspace/`, `Cartfile`, `Cartfile.resolved`, `.travis.yml`.

**Interfaces — Produces:** `public enum LegacyCleanup { public static func run(fileManager: FileManager = .default, defaults: UserDefaults = .standard, roots: [URL]? = nil) }` — once only (flag `legacyCleanup.v1` in defaults): deletes files named `Ororo.sqlite`, `Ororo.sqlite-shm`, `Ororo.sqlite-wal` in Application Support and Documents, and every `.mp4` in Documents. Before writing it, read `Ororo-Kit/Ororo-Kit/Services/Storage/StorageService.swift` and `Ororo-Player/Ororo-Player/Managers/DownloadManager.swift` and correct the names/locations above to what the old app actually used.

- [ ] **Step 1:** Tests (temp directories as `roots`): `removesLegacyStoreAndDownloads`, `leavesOtherFilesAlone`, `runsOnlyOnce`, `missingDirectoriesAreFine`.
- [ ] **Step 2:** `KIT_TEST LegacyCleanupTests` fails → implement → passes.
- [ ] **Step 3:** Both `@main` apps: call `ImageCache.configure()` and `LegacyCleanup.run()` at launch, then `AppRootView().environment(\.appEnvironment, .live())`. Move the image assets, then delete the old directories.
- [ ] **Step 4:** Rewrite `README.md`: what the app is, prerequisites (`mise`, Xcode 27), `mise exec -- tuist generate`, test commands, the 7-day reinstall note, fixture recording.
- [ ] **Step 5:** `APPS_BUILD`, full `swift test --package-path Packages/OroroKit`, all `UI_TEST` suites, `LINT` pass. `git grep -nE "Carthage|Cartfile"` prints nothing outside docs. Commit: `chore: wire apps, remove 2018 code, update README`.

### Fallback tasks (run only if the matching spike failed)

Each rewrites only its seam file plus the listed extras, keeps the public signatures from T3, and re-runs the suites of the tasks that own those files.

| Task | Change |
|---|---|
| **X-S1** | `ShelfRow.swift`: back the row with a `UIViewRepresentable` `UICollectionView` (compositional layout, `remembersLastFocusedIndexPath = true`), still reporting to `FocusMemory`. |
| **X-S2** | `DetailTransition.swift`: zoom modifiers become no-ops; add `detailCrossfadeIn()` (backdrop crossfade from the tile image, left column slides 24 pt + fades, staggered) and apply it in `DetailScreen.swift`. |
| **X-S3** | `HeroView.swift`: collapse becomes a `quick` crossfade to a compact header; paging via explicit previous/next focusable chevrons. |
| **X-S4** | Add `OroroCore/Playback/WebVTTParser.swift` (`static func parse(_ text: String) -> [Cue]`, `static func cue(at: TimeInterval, in: [Cue]) -> Cue?` by binary search; handles optional cue ids, `mm:ss.mmm` and `hh:mm:ss.mmm`, CRLF, `<i>`/`<b>`/`<br>` tags) with tests ported from `Ororo-Kit/Ororo-KitTests/SubtitleParserTests.swift` (recover it from git history) plus one test per listed case; add `Player/OverlaySubtitles.swift: SubtitleProvider` (label in `contentOverlayView`, 0.1 s observer, language menu via `transportBarCustomMenuItems` on tvOS / overlay menu on iOS, PiP disabled while on); make it `AVPlayerEngine`'s default. |
| **X-S5** | `PosterGrid.swift`: page results 200 at a time, loading the next page when focus reaches the last two rows. |
| **X-S6** | `TrailerAvailability.swift`: return nil on tvOS. |
| **X-S7** | `GlassStyle.swift`: `glassControl` uses `.ultraThinMaterial` fills. |
| **X-S8** | `AppEnvironment.live()`: construct `CatalogRepository(useETag: false)`. If durability failed, stop and raise it with the owner — the spec has no further fallback. |

---

## Wave 4 — Acceptance

### Task I3: iOS acceptance

**Needs:** I1, I2. **Files:** only fixes inside feature view files for layout defects found.

- [ ] **Step 1:** Run the `Ororo` scheme on an iPhone and an iPad simulator. Sign in; open every tab; open a show and a movie; play each with subtitles on; add to My List; search.
- [ ] **Step 2:** Fix any clipped or overlapping layout (bottom tab bar, shorter hero, stacked detail, context menus). Re-run the affected `UI_TEST` suites.
- [ ] **Step 3:** Record the pass in the PR description with one screenshot per screen. Commit: `fix(ios): layout adaptation`.

### Task I4: Hardware QA and performance (owner + Apple TV 4K 2nd gen)

**Needs:** I1, I2, any X tasks. **Files:** Create `docs/qa/2026-11-tvos-acceptance.md`.

- [ ] **Step 1:** Anti-goal checklist on the device, each item pass/fail in the QA doc: focus returns to the originating tile from Detail and from the player (20 tries across Home, Shows, Movies, Search, My List); every tab keeps scroll and focus after switching away and back; Menu behaviour matches the spec's table at each level; nothing reshuffles when a refresh lands (force one from Settings while on Home); library survives reinstall over the top; Reduce Motion variants; VoiceOver reads tiles, badges and episode rows sensibly.
- [ ] **Step 2:** Instruments → Animation Hitches, release build; record hitch time ratio for each scenario in the spec's performance budget (target < 5 ms/s), Home first paint (< 1 s warm) and catalog-ready time (< 2.5 s), and a 10-minute browse with no memory termination.
- [ ] **Step 3:** For each miss, open a follow-up task naming the screen and the measurement; fix and re-measure until the budget is met.
- [ ] **Step 4:** Commit the QA doc: `docs: tvOS acceptance and performance results`.

---

## Self-review notes

- **Spec coverage:** persistence → ST1–ST3; catalog loading → ST3, F1; navigation, Menu, focus memory → D5, F1; Home → C1, F2, F3; Shows/Movies → C1, C2, F4, F5; Detail → C4, C7, ST4, F6; Search → C3, F7; My List, Continue Watching, New Episodes → C5, ST5, F8, F13; Player → C6, F9, F10; Sign-in/Settings → F11, F12; states and errors → each F task; motion, tvOS 26 look, images → D1–D5, F3, F6; accessibility → global constraint + I4; iOS → global constraint + I3; localisation → I1; testing/CI → T1 and every task; Phase 0 → S1–S8 and X tasks; legacy cleanup, README → I2. Top Shelf is left out (spec: nice-to-have, later).
- **Addition to the spec's library model:** `upNext` stores `UpNextEntry { ref, setAt }` rather than a bare episode reference, so Continue Watching can sort up-next shows by recency.

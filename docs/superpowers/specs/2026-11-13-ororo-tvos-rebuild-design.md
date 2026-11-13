# Ororo Player — tvOS-first rebuild

Date: 2026-11-13
Status: awaiting approval

## Intent

Ororo Player is an unofficial client for [ororo.tv](https://ororo.tv) (movies and TV
shows with multi-language subtitles). The 2018 app is UIKit + Carthage, targets iOS 12 /
tvOS 10, decodes only five fields per title and presents everything as flat poster
grids. It no longer builds on current Xcode.

The owner wants a ground-up modernisation:

- **Look and feel of the Apple TV app / Netflix on TV** — cinematic, polished, with
  animations that are "super smooth and cool" and navigation that is "perfect".
- **Every piece of data the API offers rendered nicely and concisely.**
- **Modern tooling throughout, following best practices**: SwiftUI, Swift Package
  Manager only (no Carthage), no committed `.xcodeproj` — projects are generated.

Primary target is **Apple TV**. The iPhone/iPad app stays alive on shared code with a
basic adaptation; it gets dedicated design work in a later round.

## Goals

1. tvOS app with Home, Shows, Movies, My List, Search tabs, detail pages, player,
   sign-in and settings, as specified below.
2. Show all useful API fields (see *API inventory*), concisely.
3. Native tvOS focus behaviour and transitions; nothing feels janky or lost.
4. iOS app compiles and runs from the same feature code with sensible adaptation.
5. Clean modular codebase: local Swift package + thin Tuist app targets, Swift 6
   strict concurrency, tests, lint, CI.

## Non-goals (this round)

- Dedicated iPhone/iPad design (layouts merely adapt).
- Offline downloads (existing iOS feature) — *builder's call made by Claude: dropped
  this round, re-added in the iOS round.*
- Live channels — the API no longer exposes them (`/channels` → 404).
- Server-side favourites/progress — not offered by the API.
- Porting the `Transitions` coordinator library (retired, see Approaches).

## Anti-goals (would be a failure even if it "works")

- Dropped frames or stutter during focus movement or scrolling on Apple TV hardware.
- Focus that jumps somewhere unexpected, or Back/Menu that does not return the user to
  the exact tile they came from.
- A tab that forgets its scroll/focus position when you switch away and back.
- Cluttered screens: data must be present but compact (badges, one-line metadata), not
  walls of labels.
- Credentials in source code.

## Constraints

- **API**: `https://ororo.tv/api/v2`, HTTP Basic auth (email:password). Unauthenticated
  requests return 401. Known endpoints:
  - `GET /shows` — ~4,000 shows, ~3.1 MB JSON
  - `GET /shows/{id}` — show + `episodes[]`, `seasons` (count)
  - `GET /episodes/{id}` — episode + `url` (signed HLS), `download_url`, `subtitles[]`, `show_name`
  - `GET /movies` — ~7,900 movies, ~5.3 MB JSON
  - `GET /movies/{id}` — movie + `url`, `download_url`, `trailer`, `subtitles[]`, `versions`
  - 404: `/channels`, `/favorites`, `/user`, `/me`, `/watchlist`, `/shows/new`, `/movies/new`, `/api/v3/*`.
- Playback URLs are signed (`wmsAuthSign`, `validminutes=1920`); always fetch the
  detail endpoint right before playing — never persist a playback URL.
- **No per-episode artwork** exists in the API.
- **Distribution: owner's own devices only** (no TestFlight/App Store). Bundle ID
  `com.dissimirall.Ororo-Player` (tvOS + iOS share it), team `FYCJCMJ4B5`. CI does
  simulator builds only — no signing/archive. No App Review / store assets needed.
- Toolchain: Xcode 27. Deployment targets **tvOS 26 / iOS 26**.
- Image hosts vary (`ororo.tv`, `front.ororo.tv`, `front.ororo-mirror.tv`,
  `uploads.ororo-mirror.tv`); all HTTPS, no auth needed for images.

### API inventory (measured 2026-11-13)

| Field | Where | Coverage | Rendered as |
|---|---|---|---|
| `name` | all | 100% | title |
| `desc` | show, movie | ~100% | hero blurb (2–3 lines), full on detail |
| `plot` | episode | per ep | full in episode list |
| `poster_thumb` (600×900) | show, movie | 100% | poster tiles |
| `backdrop_url` | show, movie | 99% | hero, landscape tiles, detail background |
| `imdb_rating` | show, movie | ~100% | yellow "IMDb 8.3" badge |
| `imdb_id` | show, movie | most | (not shown; kept in model) |
| `year` (string) | show, movie | ~100% | metadata line; Browse decade filter |
| `array_genres` | show, movie | 100% | "Crime · Drama"; genre shelves & filters |
| `array_countries` (ISO-2) | show, movie | 100% | flag emoji on detail |
| `length` (minutes) | movie; show (often null) | movies | "2h 35m" |
| `resolution` (SD/HD) | movie, episode | most | HD badge |
| `ended` | show | 100% | "Ongoing"/"Ended"; Browse status filter |
| `user_popularity` | show (movies always 0) | 62% shows | Popular rows, Popular sort |
| `newest_video` (unix) | show | 100% | "New Episodes" row; "new ep. 2 days ago" |
| `updated_at` (unix) | all | 100% | "Recently Updated" movie row / Newest sort |
| `seasons` (count) | show detail | 100% | "2 Seasons", season pills |
| `season`, `number` (string), `airdate` | episode | per ep | "1 · Stick or Twist · 30 Mar 2025" |
| `trailer` (YouTube id) | movie detail | some | "▶ Trailer" button |
| `subtitles[] {lang, url .vtt}` | episode, movie detail | most | CC badge; subtitle picker; language list on detail |
| `versions {240p…1080p}` | episode, movie detail | per title | quality range "up to 1080p" (info only — paths are unsigned and return 403/404, so not playable) |
| `url` (signed HLS m3u8) | episode, movie detail | per title | playback (Auto quality) |
| `download_url` | detail | per title | unused this round |
| `watched_media_count` | detail | per title | unused (unclear meaning) |
| `slug`, `kinopoisk_id`, `tmdb_id`, `myshows_id`, `info.*` | various | — | decoded where cheap, not shown |

Verified formats: `subtitles[].lang` is ISO 639-1 (`en`, `ru`, `pt`…); `airdate` is
`YYYY-MM-DD`; `year` is a 4-digit string; episode `number` is a numeric string. The
list endpoints (`/shows`, `/movies`) already include `user_popularity`, `newest_video`,
`ended`, `array_genres`, `imdb_rating`, `backdrop_url`, so Home/Browse work fully from
the cached lists. The API ignores `Accept-Language` / `?locale=` — content is English
only, so Russian localisation covers UI strings only.

Fixtures: recorded responses exist (list, show detail, episode detail, movie detail).
The builder commits trimmed copies under `Tests/Fixtures/` with `url`, `download_url`
and `wmsAuthSign` values replaced by placeholders (they embed the account id). CI never
calls the live API.

Decode defensively: every field except `id` and `name` is optional; `year` and
`number` are strings; unknown keys ignored.

## Approaches considered

| | Approach | Trade-off | Decision |
|---|---|---|---|
| 1 | **Local Swift package (feature/core modules) + thin Tuist app targets** | Most code builds/tests with plain `swift test`; compiler-enforced module boundaries; two small config files | **Chosen by owner** |
| 2 | All modules as Tuist framework targets | One config file, Tuist binary caching; but nothing builds without `tuist generate` | Rejected |
| 3 | Single app target with folders | Simplest; no boundaries, slower incremental builds; fails "best practices" bar | Rejected |

Related decisions made in conversation:

- **Tuist** for project generation (owner: "if state of the art and well maintained" —
  verified: actively released, Nov 2026). Generated `.xcodeproj`/`.xcworkspace` are
  git-ignored. Old `Ororo-Player/`, `Ororo-Kit/`, `Cartfile*`, `.travis.yml` removed.
- **SwiftUI** throughout (owner approved).
- **Transitions retired**: its coordinator/flow/leak-detector concepts are replaced by
  per-tab `NavigationStack` with a typed route enum. Owner approved.
- UI directions chosen with mockups (`.superpowers/brainstorm/…/content/`):
  Home = **A · Apple TV app**; Detail = **B · Split**; Shows/Movies tabs = **C · shelves → See All = filter grid**.

## Architecture

```
ororo/
├── Project.swift            # Tuist: OroroTV (tvOS) + Ororo (iOS) app targets, tests
├── Tuist.swift / Tuist/     # Tuist config, Package.swift for external deps
├── Package.swift            # local package "OroroKit"
├── Sources/
│   ├── OroroAPI/            # Endpoint, APIClient (async/await, URLSession), Codable DTOs
│   ├── OroroStore/          # CatalogRepository (cache + refresh), SwiftData models
│   │                        #   (MyListItem, PlaybackProgress, Preferences), Keychain
│   ├── OroroDesign/         # Tokens (type, spacing, colours), Tiles, Badges, focus
│   │                        #   styles, BackdropView, image pipeline wrapper
│   └── OroroFeatures/       # Home, Browse, Detail, Search, MyList, Player,
│                            #   SignIn, Settings, AppRoot (tabs + routing)
├── Apps/
│   ├── TV/                  # @main App, assets, Info.plist, Top Shelf ext (later)
│   └── iOS/                 # @main App, assets, Info.plist
└── Tests/                   # Swift Testing: OroroAPITests, OroroStoreTests, OroroFeaturesTests
```

Module dependency direction: `Features → Design, Store → API`. `Design` does not depend
on `Store`/`API` (takes plain view models). Features may be split into one module per
feature later; start with one `OroroFeatures` module unless compile times hurt.

- **Language**: Swift 6 language mode, strict concurrency complete. `@MainActor` view
  models using `@Observable`. Networking/repository types are `Sendable` actors or
  structs.
- **Dependencies**: only **Nuke / NukeUI** (image loading with memory + disk cache,
  prefetching, decompression off-main). Everything else first-party. Managed via SPM.
- **Dependency injection**: an `AppEnvironment` (API client, repositories, image
  pipeline) passed via SwiftUI `Environment`; previews and tests inject fakes.
- **Persistence**: SwiftData for My List + playback progress + preferences. Models are
  CloudKit-compatible from day one (no unique constraints, all properties optional or
  defaulted, optional relationships; de-duplicate on read). iCloud sync is enabled
  when the team has the iCloud capability; otherwise the same store runs local-only —
  a configuration switch, not a redesign. *Claude's call.* Catalog lists are
  cached as raw JSON files in Caches and decoded on launch; refreshed in background
  (stale-while-revalidate). Credentials in Keychain only.
- **Lint/format**: SwiftLint via SPM build-tool plugin, strict; `swift-format` config.
- **CI**: GitHub Actions on macOS runner: `tuist install && tuist generate`,
  lint, build both apps, run tests.
- **Localisation**: String Catalogs; ship English + Russian (existing app has both).

## Navigation

- Root: `TabView` with tvOS top tab bar: **Home · Shows · Movies · My List · Search**,
  plus Settings reachable as a trailing tab/gear (tvOS convention).
- Each tab owns a `NavigationStack(path:)` bound to a `[Route]` held in that tab's
  router; `Route` is a `Hashable` enum: `.show(id)`, `.movie(id)`, `.browse(BrowseQuery)`.
- Player is presented full-screen (`fullScreenCover`), not pushed.
- Menu/Back pops exactly one level; focus returns to the originating tile
  (`@FocusState` + `prefersDefaultFocus` / `focusScope` restoration).
- Each tab preserves scroll position and focus when switching tabs (tabs are kept
  alive; scroll position via `ScrollPosition`).
- Unauthenticated → Sign-in screen replaces root; sign-out returns to it.

## Screens

### Home (direction A)

- **Hero**: full-screen, auto-advancing every ~8 s (pauses while focused/interacted),
  page dots. Items: top ~6 by `user_popularity` (shows) mixed with highest-rated recent
  movies. Shows: backdrop, title, IMDb badge, year, genres, HD/CC badges, 2–3 line
  `desc`, buttons **Play / Resume SxEy** and **+ My List**.
- Swipe down: hero collapses (spring) and shelves scroll up. Shelves (landscape 16:9
  backdrop tiles, title below on focus):
  1. Continue Watching (local progress; progress bar on tile) — hidden if empty
  2. Popular Shows (`user_popularity` desc)
  3. New Episodes (`newest_video` desc)
  4. Top Rated Movies (`imdb_rating` desc, minimum year threshold left to builder)
  5. Recently Added Movies (`updated_at` desc)
  6. My List (if not empty)
  7. A few genre rows (largest genres)

### Shows / Movies tabs (direction C)

- Opens on **poster shelves** (2:3): Popular Now (shows) / Recently Updated, Top Rated,
  then one row per genre ordered by title count. Row header shows count + "See All ›".
- **Browse All** button at top; each "See All" pushes the **filter grid** pre-set:
  - Filters: Genre (chips), Decade, Min IMDb (Any/6+/7+/8+), Status (Any/Ongoing/Ended — shows only)
  - Sort: Popular (shows) · Rating · Newest · A–Z
  - Dense poster grid; footer strip with focused title's name · IMDb · year · status.
- All filtering is local (catalog is in memory).

### Detail (direction B · Split)

- Full-bleed backdrop, heavily darkened.
- **Left column (fixed)**: title, metadata line (IMDb · year · Ongoing/Ended or runtime ·
  HD · CC), genres · country flags, full description, vertical buttons:
  - Shows: **Resume SxEy** / **Play S1 E1**, **+ My List**, **Subtitles: EN**
  - Movies: **Play / Resume**, **▶ Trailer**, **+ My List**, **Subtitles**
  - Trailer (owner's choice): opens `youtube://watch/<id>` in the YouTube app; the
    button is hidden when the app is not installed (`canOpenURL`, with `youtube` in
    `LSApplicationQueriesSchemes`) or `trailer` is absent.
  - Footer: subtitle languages list, quality range.
- **Right column**:
  - Shows: season pills; vertical episode list rows: number, name, airdate, HD, full
    plot, watch progress; focused row highlighted (white). Select → play.
  - Movies: no list; right side shows the backdrop un-obscured / additional facts.
- Initial focus: Resume/Play button.

### Search

- Native `.searchable` tvOS keyboard; live results as two poster rows (Shows, Movies).
- Local matching over the cached catalog: title (diacritic/case-insensitive, prefix and
  word matches), genre names, 4-digit year.

### My List

- Continue Watching row (landscape) + My List poster grid. Long-press/context menu to
  remove.

### Player

- `AVPlayerViewController` (native transport bar, scrubbing, PiP, Siri).
- Start: fetch episode/movie detail for fresh signed `url`; if progress > ~1 min and
  < 95%, ask **Resume from 23:14 / Start over**.
- **Subtitles**: the API delivers sidecar `.vtt` files, not in-stream tracks. Render
  them with an overlay (port of existing `SubtitleParser`) synced to player time,
  chosen via a custom transport-bar menu (`transportBarCustomMenuItems`). Default
  language from Settings.
- **Quality**: HLS `url` only (adaptive bitrate). *No manual quality picker*: verified
  2026-11-13 that `versions` paths are unsigned and return 403/404 on every host; only the
  single signed `url` (HLS) and `download_url` (top-quality MP4) are playable.
- **Next Episode**: contextual action near end of episode; autoplay countdown.
- Progress saved periodically (~every 10 s) and on exit; ≥95% marks watched.

### Sign-in & Settings

- Sign-in: email + password fields, validates by calling `/shows` (HEAD or small
  request); stores in Keychain. Error states for wrong credentials / offline.
- Settings: account (sign out), default subtitle language, clear image cache, app version.

## Motion & focus

- Use native focus effects first: `.buttonStyle(.card)` / `.hoverEffect(.highlight)`
  lift + parallax on tiles; `.focusSection()` per shelf so vertical moves land sensibly.
- Backdrop crossfade (~0.35 s) when focus changes on Home/Browse; debounce rapid
  focus movement so images don't thrash.
- Hero collapse: spring animation tied to scroll offset.
- Tile → Detail: zoom navigation transition (`.navigationTransition(.zoom…)`) where
  supported, otherwise matched fade.
- Images: fade-in on load; prefetch next row(s) via Nuke prefetcher; request correctly
  sized images (posters are 600×900; backdrops downsampled on decode).
- Performance budget: 60 fps on Apple TV 4K (2nd gen) during focus traversal of a
  shelf; Home first paint < 1 s from cached catalog.

## iOS adaptation (basic)

Same features compile for iOS; layouts adapt via size classes: bottom tab bar, hero
becomes shorter, detail split becomes stacked (info then episodes). No iOS-specific
design polish this round.

## Testing

- **Swift Testing** for: DTO decoding against recorded fixtures (real responses
  trimmed, credentials-free), repository filtering/sorting/search, progress logic,
  route handling, VTT parser (port existing tests).
- Snapshot/preview coverage of key views with fake data (SwiftUI previews compile in CI).
- Manual QA on Apple TV hardware or simulator for focus/animation.

## Left to the builder

- Exact visual tokens (font sizes, spacing, colours) within the mockup look.
- Hero item selection algorithm details and Top Rated year threshold.
- Whether Features splits into per-feature modules.
- Top Shelf extension (nice-to-have; may follow later).
- Exact Tuist version and config layout.

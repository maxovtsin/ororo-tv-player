# Ororo Player — tvOS-first rebuild

Date: 2026-11-13
Status: revised after review (rev 2), awaiting approval

Items marked **[spike]** are platform behaviours nobody has tested yet. Each has a
decided primary and a decided fallback; *Phase 0* picks between them on real hardware
before feature work starts.

## Intent

Ororo Player is an unofficial client for [ororo.tv](https://ororo.tv) (movies and TV
shows with multi-language subtitles). The 2018 app is UIKit + Carthage, targets iOS 12 /
tvOS 12, decodes only five fields per title and presents everything as flat poster
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

1. tvOS app with Home, Shows, Movies, My List, Search and Settings tabs, detail pages,
   player and sign-in, as specified below.
2. Show all useful API fields (see *API inventory*), concisely.
3. Native tvOS focus behaviour and transitions; nothing feels janky or lost.
4. iOS app compiles and runs from the same feature code with sensible adaptation.
5. Clean modular codebase: local Swift packages + thin Tuist app targets, Swift 6
   strict concurrency, tests, lint, CI.

## Non-goals (this round)

- Dedicated iPhone/iPad design (layouts merely adapt).
- Offline downloads (existing iOS feature) — dropped this round, re-added in the iOS
  round. *Claude's call.*
- Live channels — the API no longer exposes them (`/channels` → 404).
- Server-side favourites/progress — not offered by the API.
- **Sync between devices** — needs iCloud, which needs a paid developer account. My
  List and progress are per device.
- tvOS multi-user profiles — one library per device.
- Migrating the 2018 app's Core Data favourites. On first launch the new app deletes
  the legacy store and (iOS) the legacy downloads folder. *Claude's call.*
- Porting the `Transitions` coordinator library (retired, see Approaches).

## Anti-goals (would be a failure even if it "works")

- Dropped frames or stutter during focus movement or scrolling on Apple TV hardware.
- Focus that jumps somewhere unexpected, or Back/Menu that does not return the user to
  the exact tile they came from.
- A tab that forgets its scroll/focus position when you switch away and back.
- Content that reshuffles under the user's focus (e.g. when a background refresh lands).
- Cluttered screens: data must be present but compact (badges, one-line metadata), not
  walls of labels.
- Losing My List or watch progress.
- Credentials in source code.

## Constraints

- **API**: `https://ororo.tv/api/v2`, HTTP Basic auth (email:password). Unauthenticated
  requests return 401. Known endpoints:
  - `GET /shows` — ~4,000 shows, ~3.1 MB JSON, no pagination
  - `GET /shows/{id}` — show + `episodes[]`, `seasons` (count)
  - `GET /episodes/{id}` — episode + `url` (signed HLS), `download_url`, `subtitles[]`, `show_name`
  - `GET /movies` — ~7,900 movies, ~5.3 MB JSON, no pagination
  - `GET /movies/{id}` — movie + `url`, `download_url`, `trailer`, `subtitles[]`, `versions`
  - 404: `/channels`, `/favorites`, `/user`, `/me`, `/watchlist`, `/shows/new`, `/movies/new`, `/api/v3/*`.
- Playback URLs are signed (`wmsAuthSign`, `validminutes=1920` = 32 h); always fetch
  the detail endpoint right before playing — never persist a playback URL.
- **No per-episode artwork** exists in the API.
- **Free Apple developer account (personal team `FYCJCMJ4B5`).** Consequences:
  - No iCloud / CloudKit / key-value sync, no associated domains.
  - Device builds expire after 7 days; the owner reinstalls from Xcode. Installing over
    the top keeps app data and Keychain; **deleting the app loses the library**.
  - Distribution is the owner's own devices only. No TestFlight/App Store, no App
    Review, no store assets.
- **tvOS has no guaranteed persistent file storage**: files live in Caches and may be
  purged while the app is not running. Only `UserDefaults` (limit ~500 KB) and the
  Keychain are durable. This drives the *Persistence* design.
- Bundle ID `com.dissimirall.Ororo-Player` (tvOS + iOS share it). CI does simulator
  builds only — no signing/archive.
- Toolchain: Xcode 27. Deployment targets **tvOS 26 / iOS 26**.
- Image hosts vary (`ororo.tv`, `front.ororo.tv`, `front.ororo-mirror.tv`,
  `uploads.ororo-mirror.tv`); all HTTPS, no auth needed for images.

### API inventory (measured 2026-11-13, re-checked against the recordings)

"List" = present in `/shows` / `/movies`; "detail" = only in the per-id endpoint.

| Field | Where | Coverage | Rendered as |
|---|---|---|---|
| `name` | all | 100% | title |
| `desc` | show, movie (list) | 99% | hero blurb (2–3 lines), full on detail |
| `plot` | episode (in show detail) | per ep | episode row |
| `poster_thumb` (600×900) | show, movie (list) | 100% | poster tiles |
| `backdrop_url` | show, movie (list) | 98–99% (61 shows, 49 movies lack it) | hero, landscape tiles, detail background |
| `imdb_rating` | show, movie (list) | 99% | yellow "IMDb 8.3" badge |
| `imdb_id` | show, movie (list) | 100% | (not shown; kept in model) |
| `year` (string) | show, movie (list) | 100% | metadata line; decade filter; Year sort |
| `array_genres` (27 distinct) | show, movie (list) | 98–99% | "Crime · Drama"; genre shelves & filters |
| `array_countries` (ISO-2) | show, movie (list) | 95–98% | flag emoji on detail |
| `length` (minutes) | movie list 100%; show list 74% | — | "2h 35m" (movies), "45m episodes" (shows) |
| `resolution` (SD/HD) | **movie list**; episode (in show detail). **Not in show list** | 100% | HD badge on movies everywhere; on shows only on detail |
| `ended` (bool) | show (list) | 100% | "Ongoing"/"Ended"; status filter |
| `user_popularity` | show list (62% non-zero); movies always 0 | — | Popular rows, Popular sort (shows only) |
| `newest_video` (unix) | show (list) | 99% | personal "New Episodes" row (detection); "Latest Releases" row; "new ep. 2 days ago" |
| `updated_at` (unix) | all | 100% | "Recently Updated" rows and sort |
| `seasons` (count) | show detail | 100% | "2 Seasons" |
| `season` (int), `number` (string), `airdate` | episode (in show detail) | per ep | "1 · Stick or Twist · 30 Mar 2025" |
| `versions {240p…1080p}` | episode (in show detail), movie detail | per title | quality range "up to 1080p" (info only — paths are unsigned and return 403/404) |
| `trailer` (YouTube id) | movie detail | some | "▶ Trailer" button |
| `subtitles[] {lang, url .vtt}` | **episode detail, movie detail only** | most | CC badge; subtitle track; language list on detail |
| `url` (signed HLS m3u8) | episode detail, movie detail | per title | playback (Auto quality) |
| `download_url` | detail | per title | unused this round |
| `watched_media_count` | detail | per title | unused (looks like a global view count) |
| `slug`, `kinopoisk_id`, `tmdb_id`, `myshows_id`, `info.*` | various | — | decoded where cheap, not shown |

Consequences of where fields live:

- Home, Browse and Search work fully from the cached lists.
- **CC badges and subtitle languages are never shown from list data.** They appear on
  Detail once the relevant detail response has arrived.
- A show's quality range and HD badge come from `episodes[]` in `/shows/{id}`.

Verified formats: `subtitles[].lang` is ISO 639-1; `airdate` is `YYYY-MM-DD`; `year` is
a 4-digit string; episode `number` is a numeric string, `season` an int. The API
ignores `Accept-Language` / `?locale=` — content is English only.

Decode defensively: every field except `id` and `name` is optional; unknown keys
ignored; a single undecodable item is skipped, not fatal for the list.

**Fixtures.** Recordings currently sit in a temporary folder
(`/private/tmp/claude-501/-Users-max-Projects-ororo/5dc192cb-38d7-45c0-a978-65e820e08a63/scratchpad/api/`)
which will disappear. Milestone 1 adds `Scripts/record-fixtures.sh` (credentials from
`ORORO_EMAIL` / `ORORO_PASSWORD` env vars) that records, trims the lists to ~200 items
and replaces `url`, `download_url` and `wmsAuthSign` values with placeholders (they
embed the account id). Output is committed under `Packages/OroroKit/Tests/Fixtures/`.
CI never calls the live API.

## Approaches considered

| | Approach | Trade-off | Decision |
|---|---|---|---|
| 1 | **Local Swift packages (core + UI modules) + thin Tuist app targets** | Compiler-enforced module boundaries; non-UI code tests with plain `swift test`; UI code needs a simulator | **Chosen by owner** |
| 2 | All modules as Tuist framework targets | One config file, Tuist binary caching; but nothing builds without `tuist generate` | Rejected |
| 3 | Single app target with folders | Simplest; no boundaries, slower incremental builds | Rejected |

Related decisions:

- **Tuist** for project generation. Generated `.xcodeproj`/`.xcworkspace` are
  git-ignored. Old `Ororo-Player/`, `Ororo-Kit/`, `Cartfile*`, `.travis.yml` removed.
- **SwiftUI** throughout (owner approved).
- **Transitions retired**: replaced by per-tab `NavigationStack` with a typed route
  enum. Owner approved.
- UI directions chosen with mockups (`.superpowers/brainstorm/…/content/`):
  Home = **A · Apple TV app**; Detail = **B · Split**; Shows/Movies tabs = **C · shelves → See All = filter grid**.
- **No SwiftData / CloudKit** (rev 2): without a paid account there is no sync, and on
  tvOS a SwiftData store sits in purgeable Caches. See *Persistence*. *Claude's call.*
- **Subtitles as a native HLS track**, overlay as fallback (rev 2). See *Player*.
  *Claude's call.*

## Architecture

```
ororo/
├── Project.swift              # Tuist: OroroTV (tvOS) + Ororo (iOS) app targets
├── Tuist.swift                # Tuist config
├── Packages/
│   ├── OroroKit/              # no UI; platforms tvOS, iOS, macOS → `swift test`
│   │   ├── Package.swift
│   │   ├── Sources/
│   │   │   ├── OroroCore/     # domain models + pure logic: shelf building, filter/
│   │   │   │                  #   sort, search index, episode ordering, next-episode,
│   │   │   │                  #   progress rules, Route
│   │   │   ├── OroroAPI/      # Endpoint, APIClient (async/await, URLSession), DTOs
│   │   │   │                  #   → Core models
│   │   │   └── OroroStore/    # CatalogRepository (cache + refresh), LibraryStore
│   │   │                      #   (My List, progress, preferences), Keychain
│   │   └── Tests/             # OroroCoreTests, OroroAPITests, OroroStoreTests, Fixtures/
│   └── OroroUI/               # platforms tvOS, iOS; tested on a simulator
│       ├── Package.swift      # declares Nuke
│       ├── Sources/
│       │   ├── OroroDesign/   # tokens (type, spacing, colour, Motion), tiles, badges,
│       │   │                  #   focus styles, BackdropView, image pipeline wrapper
│       │   └── OroroFeatures/ # Home, Browse, Detail, Search, MyList, Player,
│       │                      #   SignIn, Settings, AppRoot (tabs + routing)
│       └── Tests/             # OroroFeaturesTests (view models)
├── Apps/
│   ├── TV/                    # @main App, assets, Info.plist
│   └── iOS/                   # @main App, assets, Info.plist
└── Scripts/                   # record-fixtures.sh
```

Dependency direction: `Features → Design, Store → API → Core`. `Design` depends only
on Nuke and takes plain values. Rule for where code goes: **if it can be written
without importing SwiftUI, it lives in `OroroCore`** and is tested with `swift test`.

- **Language**: Swift 6 language mode, strict concurrency complete. `@MainActor` view
  models using `@Observable`. `APIClient`, `CatalogRepository` and `LibraryStore` are
  actors; models are `Sendable` structs.
- **Dependencies**: only **Nuke / NukeUI**. Everything else first-party.
- **Dependency injection**: an `AppEnvironment` (API client, repositories, image
  pipeline) passed via SwiftUI `Environment`; previews and tests inject fakes.
- **Lint**: SwiftLint only (it also owns formatting rules; no `swift-format`). Run as a
  CLI step in CI and locally, not as a build-tool plugin. Existing `.swiftlint.yml` is
  updated, not replaced.
- **CI**: GitHub Actions, macOS runner with Xcode 27 pinned. Steps: SwiftLint →
  `swift test` in `Packages/OroroKit` → `tuist generate` → build both apps and run
  `OroroFeaturesTests` on a tvOS simulator. If hosted runners do not have Xcode 27 yet,
  CI runs the first two steps only until they do.
- **Localisation**: String Catalogs; English + Russian UI. Genre names are mapped
  through the catalog (27 known genres) with the API string as fallback. Dates,
  durations and country names use `FormatStyle` / `Locale`, never hand-built strings.

### Persistence

| Data | Where | Durable? |
|---|---|---|
| Credentials | Keychain (`AfterFirstUnlock`) | yes |
| My List, progress, watched flags, up-next, preferences | `LibraryStore` | yes |
| Catalog lists, Home snapshot | files in Caches | no — refetched |
| Images | Nuke disk cache in Caches, capped at 500 MB | no |
| Detail responses | memory only, 10 min TTL, signed URLs stripped | no |

**`LibraryStore`** is an actor holding one versioned `Codable` value in memory. It is
written as JSON to `UserDefaults` on tvOS (the only durable option) and to a file in
Application Support on iOS, behind one `LibraryPersistence` protocol.

- Contents: `myList [{kind, id, addedAt}]`, `progress [{kind, id, showID?, season?,
  number?, episodeName?, position, duration, updatedAt}]`, `watched [episode/movie id]`,
  `upNext [showID: {episodeID, season, number}]`,
  `followed [showID: {seenNewestVideo}]` (see *New Episodes rules*), `preferences`.
- No titles or artwork are stored: tiles resolve `id` against the in-memory catalog. An
  entry whose title has left the catalog is hidden but kept.
- Size budget 300 KB, enforced by caps: 500 My List items, 200 progress entries, 5,000
  watched ids. Oldest entries are pruned first.
- Writes: memory is updated immediately; disk is flushed at most every 10 s during
  playback, and immediately on pause, player dismissal and app backgrounding.
- **[spike]** confirm the library survives an over-the-top reinstall and a simulated
  low-storage purge.

### Catalog loading

- **Sign-in is the first catalog load**: `/shows` with the entered credentials both
  validates them and warms the cache. `/movies` follows.
- **First launch**: a branded loading screen with byte progress (~8.4 MB), then Home
  fades in.
- **Later launches**: Home renders from `home-snapshot.json` (the ~150 titles its
  shelves need, written after every refresh), while the full lists decode off the main
  thread. Other tabs show skeleton shelves until the catalog is ready.
- **Refresh**: on launch and on foregrounding when the cache is older than 6 h, plus
  "Refresh catalog" in Settings. Uses `If-None-Match` if the server sends an `ETag`
  **[spike]**, otherwise a full fetch.
- **Applying a refresh**: the new catalog is swapped in atomically, but a screen keeps
  the snapshot it was built from while it is visible. Shelves rebuild the next time the
  screen appears. Nothing moves under the user's focus.
- Fetch failure with a cache: keep using the cache silently, retry on next trigger.
  Without a cache: full-screen error with Retry.

## Navigation

- Root: `TabView` with the tvOS top tab bar: **Home · Shows · Movies · My List ·
  Search · Settings** (Settings is the trailing tab, gear icon only).
- Each tab owns a `NavigationStack(path:)` bound to a `[Route]` held in that tab's
  router; `Route` is a `Hashable` enum: `.show(id)`, `.movie(id)`, `.browse(BrowseQuery)`.
- Player is presented full-screen (`fullScreenCover`), not pushed.
- Unauthenticated → Sign-in replaces root; sign-out returns to it.

### Menu / Back

| Where | Menu does |
|---|---|
| Player | dismisses to the screen that started playback |
| Pushed screen | pops one level; focus returns to the originating tile |
| Tab root, scrolled down | scrolls to top and focuses the first element |
| Tab root, at top | moves focus to the tab bar |
| Tab bar | exits to the tvOS Home screen |

### Focus memory

This is the highest-risk part of the app, so the mechanism is specified.

- Every focusable tile has a stable `FocusID(screen, shelf, item)`. The same title in
  two shelves has two different ids.
- Each tab's router owns a `FocusMemory` that outlives tab switches and pushes. Per
  screen it stores: the last focused `FocusID`, the last focused item per shelf, each
  shelf's horizontal `ScrollPosition`, and the vertical `ScrollPosition`.
- Restoring (after a pop, tab switch or player dismissal): scroll positions are
  restored by id first so the lazy tile exists, then focus is set to the stored id via
  `defaultFocus` / `@FocusState`.
- Each shelf is a `.focusSection()`. Moving vertically into a shelf lands on that
  shelf's remembered item, otherwise the nearest tile.
- After autoplay has advanced to another episode, dismissal focuses the episode that
  was playing last, switching season if needed.
- If the remembered item no longer exists (catalog refreshed), focus falls back to the
  same index in that shelf, then to the shelf's first tile.
- **[spike]** fallback if pure SwiftUI cannot meet the acceptance tests in *Phase 0*:
  shelves are wrapped `UICollectionView`s with `remembersLastFocusedIndexPath`.

## Screens

Every screen defines its loading, empty and error state; see *States and errors*.

### Home (direction A)

**Hero** — full-screen, with page dots (indicators, not focusable).

- Items: 6, each must have a backdrop and a description. 3 shows with the highest
  `user_popularity` among those with a new episode in the last 30 days, and 3 movies
  with the highest `imdb_rating` among those updated in the last 30 days. Exact
  weighting is left to the builder.
- Content: backdrop, title, IMDb badge, year, genres, Ongoing/Ended (shows), runtime
  and HD (movies), 2–3 lines of `desc`. No CC badge (not in list data).
- Buttons: **Play** (movies) or **Play S1 E1 / Resume S2 E3** (shows, from local
  progress and up-next — no network), and **+ My List**.
- Paging: the items are a horizontal strip of pages, each with its own buttons. Left/right
  (click or swipe) moves between the buttons; moving past the outermost button moves focus
  onto the neighbouring page and the strip slides with it, backdrop included. A click past
  the first or last page wraps around.
- Auto-advance: every 8 s while focus is in the hero **and** the remote has been idle
  for 8 s. It stops when focus is in the shelves, the app is inactive, or Reduce Motion
  is on.

**Dimming** — the hero keeps its size; it is dimmed while focus is in the shelves. Moving
between the hero and the shelves is one vertical scroll: while focus is in the hero the
page sits at the top (full-bleed backdrop, first shelf header peeking). No per-frame
geometry reads feed state.

**Shelves** — landscape 16:9 backdrop tiles, title appears below on focus. Each shelf
shows at most 30 items.

1. Continue Watching (progress bar on tile) — hidden if empty
2. New Episodes (shows the user follows; "New" badge on tile) — hidden if empty
3. Popular Shows (`user_popularity` desc)
4. Latest Releases (all shows, `newest_video` desc)
5. Top Rated Movies (`imdb_rating` desc, minimum year left to builder)
6. Recently Updated Movies (`updated_at` desc)
7. My List — hidden if empty
8. Four genre rows (largest genres), each in Top Picks order: highest IMDb rating
   first among shows with `user_popularity` > 0 / movies from the last 15 years, then
   the remaining rated titles by rating, unrated last. "See All" opens the grid with
   the Top Picks sort (also offered in the Sort menu).

Rows 1 and 2 follow the *Continue Watching rules* and *New Episodes rules* under
My List. Select on a tile in either row plays the episode or movie directly.

Titles without a backdrop get a placeholder tile: the poster blurred to fill, with the
title text on top.

### Shows / Movies tabs (direction C)

- Opens on **poster shelves** (2:3), each capped at 30 items and ending in a "See All"
  tile. Shows: Popular Now, Latest Releases, Top Rated. Movies: Recently Updated, Top
  Rated. Then one row per genre, ordered by title count. Row header shows the count.
- **Browse All** button at top; each "See All" pushes the **filter grid** pre-set:
  - Genre: single-select chips (All + genres). *Claude's call.*
  - Decade, Min IMDb (Any/6+/7+/8+), Status (Any/Ongoing/Ended — shows only).
  - Sort: Popular (shows only) · Rating · Year · Recently Updated · A–Z. Default is
    Popular for shows and Recently Updated for movies. Titles with zero popularity sort
    after the rest, ordered by rating.
  - One scroller: the title, result count, filter menus and genre chips scroll away
    with the grid and come back when focus moves up. Filter changes crossfade only
    the grid, so focus stays on the control that was used.
  - Poster grid sized to the width (6 × 260 pt on tvOS, 3+ columns on iPhone/iPad);
    each poster is captioned with its name and "year · ★ rating".
  - Menus read "Sort ↕ Popular", then "Decade", "IMDb", "Status"; a set filter shows its
    value ("2010s", "IMDb 7+") and is highlighted, as is the selected genre chip.
    **Reset Filters** appears in the menu row while the query differs from the default.
  - No results: "No titles match", a hint, and a **Reset Filters** button, below the
    filters so they can be changed in place.
- Filter state lives in the route's `BrowseQuery`, so Back and tab switches keep it.
- All filtering is local and runs off the main thread.
- **[spike]** the grid must hold the hitch budget with all 7,920 movies.

### Detail (direction B · Split)

Opens instantly from catalog data; detail responses fill in afterwards.

- Full-bleed backdrop, darkened by a left-to-right gradient.
- **Left column (fixed)**:
  - Title; metadata line: IMDb · year · runtime (movies) or "2 Seasons" · Ongoing/Ended
    (shows) · HD. Shows within 14 days of a new episode add "new ep. 2 days ago".
  - Genres · country flags; full description.
  - Buttons — shows: **Resume SxEy / Play S1 E1**, **+ My List**, **Subtitles: English**.
    Movies: **Play / Resume**, **▶ Trailer**, **+ My List**, **Subtitles: English**.
  - The Subtitles button sets the app-wide preferred language (Off + languages); it is
    the same preference as in Settings.
  - Footer: subtitle languages · quality range. It fades in when data arrives: for
    movies from `/movies/{id}`; for shows the quality range from `episodes[]`, and the
    languages from a prefetch of the resume/first episode's detail.
- **Trailer**: opens `youtube://watch/<id>`. Hidden when `trailer` is absent or
  `canOpenURL` is false (`youtube` in `LSApplicationQueriesSchemes`). **[spike]** if
  the tvOS YouTube app does not honour the scheme, the button is omitted on tvOS.
- **Right column — shows**:
  - Season pills in a horizontally scrolling row, built from the distinct `season`
    values in `episodes[]` (season 0 is labelled "Specials" and placed last).
  - Initial season: the one containing the resume/up-next episode, else the first.
  - Episodes sorted by numeric `number`; an unnamed episode is "Episode N".
  - Row: number, name, airdate, HD/SD, two lines of plot, progress bar or watched
    checkmark. **The focused row expands to the full plot** (max 6 lines) and is
    highlighted white. Select → play.
  - Long-press menu: Play from Beginning, Mark as Watched / Unwatched.
  - Until `/shows/{id}` arrives: six skeleton rows.
- **Right column — movies**: empty; the backdrop shows through a lighter gradient.
- **Focus**: starts on Resume/Play. Moving right lands on the resume/up-next episode
  (else the first row), afterwards on the last focused row. Moving left returns to the
  last focused button.

### Search

- Native `.searchable` tvOS keyboard; results as two poster rows (Shows, Movies), up to
  50 each.
- Before typing: Popular Shows and Top Rated Movies rows.
- Matching over a prebuilt, case- and diacritic-folded index, on a background actor,
  150 ms debounce, stale queries cancelled.
- Ranking: exact title → title prefix → word prefix → substring → genre name → 4-digit
  year. Ties break by popularity (shows) or rating (movies).
- No matches: "No results for '…'".

### My List

- Continue Watching row (landscape), New Episodes row (landscape), then the My List
  poster grid, newest first. Empty rows are hidden.
- Empty: a short explanation and a button to the Shows tab.

**What is remembered** (all in `LibraryStore`, per device): the position in every
episode or movie in progress, which episodes and movies were watched to the end, each
show's up-next episode, and which shows the user follows.

**Continue Watching rules** (also used on Home):

- One entry per movie in progress, and **one entry per show**: its most recent
  in-progress episode, otherwise its up-next episode.
- Finishing an episode (≥ 95% or played to end) marks it watched, removes its progress
  and sets the show's up-next to the following episode. No following episode → the user
  is caught up and the show leaves the row.
- Finishing a movie marks it watched and removes it from the row.
- Sorted by last activity.

**New Episodes rules** (also used on Home):

- A show is **followed** once the user has started any episode of it or added it to
  My List. Removing it from My List un-follows it only if nothing was ever watched.
- Detection needs no extra requests: each followed show stores `seenNewestVideo`, the
  show's `newest_video` at the moment it was followed. After every catalog refresh, a
  followed show whose `newest_video` is newer than the stored value **has a new
  episode**.
- A show appears in exactly one row. If it is already in Continue Watching it stays
  there and its tile gains a "New" badge; otherwise it appears in New Episodes.
- For shows in the row the app fetches `/shows/{id}` in the background (at most 10 per
  refresh, one at a time) to resolve the episode: the first unwatched episode after the
  last watched one. The tile then reads "S2 E5 · New"; until resolved it reads "New
  episode · 2 days ago". Several new episodes: "3 new episodes", starting at the first.
- Select plays the resolved episode. For a My List show the user never started, Select
  opens Detail on the newest season instead.
- A show leaves the row when the user starts the new episode (it moves to Continue
  Watching), marks it watched, or picks **Dismiss** from the long-press menu. At that
  point `seenNewestVideo` is set to the current `newest_video`.
- Sorted by release time, newest first. Max 30.
- Assumption to confirm with the fixtures over a few days: `newest_video` changes only
  when an episode is added. If it also moves on re-uploads, detection additionally
  requires the resolved episode to be unwatched before the show is listed.

**Long-press menu on any title tile, anywhere**: Add to / Remove from My List. On
Continue Watching tiles also: Remove from Continue Watching, Mark as Watched, Go to
Show. On New Episodes tiles also: Dismiss, Mark as Watched, Go to Show.

### Player

`AVPlayerViewController` (native transport bar, scrubbing, PiP, Siri).

**Start**: Select → the button shows a spinner → fetch episode/movie detail for a fresh
`url` → if progress is between 1 min and 95%, ask **Resume from 23:14 / Start Over** →
present.

**Subtitles** — the API delivers sidecar `.vtt` files, not in-stream tracks.

- *Primary: inject them as native HLS subtitle tracks.* An
  `AVAssetResourceLoaderDelegate` serves a synthetic master playlist under a custom
  scheme: the original variants (rewritten to absolute HTTPS URLs) plus one
  `EXT-X-MEDIA:TYPE=SUBTITLES` entry per language, each pointing to a one-segment
  playlist that references the `.vtt` URL. This gives the native subtitle menu, system
  caption styling, PiP and identical behaviour on iOS.
- **[spike]** pass criteria: cues within ±100 ms at start, mid-stream and after a seek,
  on three titles including a Russian track.
- *Fallback: overlay.* A new `WebVTTParser` (the 2018 `SubtitleParser` is **not**
  ported: it requires numeric cue ids, fails on `mm:ss.mmm` timestamps and CRLF files,
  and force-unwraps) feeding a label in `contentOverlayView`, updated every 0.1 s by
  binary search; language chosen via `transportBarCustomMenuItems` on tvOS and an
  on-screen menu on iOS; PiP disabled while overlay subtitles are on. The existing
  parser tests are ported as cases for the new parser.
- Selection: the preferred language (default English) is applied automatically. If the
  title lacks it, subtitles are off, silently. Changing the language or turning
  subtitles off in the player updates the preference.

**Quality**: the HLS `url` only (adaptive bitrate). No manual quality picker.

**Next episode**

- Order: next `number` in the season, else the first episode of the next season;
  Specials are never auto-selected.
- A **Next Episode** contextual action appears for the last 40 s. At the end, the next
  episode starts after a 5 s countdown that the user can cancel.
- After three consecutive autoplays with no remote input, ask **Still watching?**
- No next episode → the player dismisses to Detail at the end.
- "Autoplay next episode" is a setting (default on).

**Progress**: recorded every 10 s, flushed as described in *Persistence*.

**Failures**

| Case | Behaviour |
|---|---|
| Detail fetch fails before playback | alert on the originating screen: Retry / Cancel |
| Response has no `url`, or the stream returns 403 | "Can't play this title. Check your ororo.tv subscription." |
| Player item fails mid-stream, or the app returns to the foreground more than 30 h after the URL was fetched | refetch detail, swap the item, seek to the last position; one automatic attempt, then Retry / Close |
| Network stall | native buffering indicator; after 30 s treated as a mid-stream failure |
| A subtitle file fails to load | playback continues without that track |

### Sign-in & Settings

- **Sign-in**: email + password with `textContentType` `.username` / `.password` and
  the email keyboard, so the iPhone keyboard hand-off works. Validation is the `/shows`
  fetch. Errors: wrong credentials (401), offline, server error — each with its own
  message.
- **A 401 during a session** (password changed): a re-sign-in sheet over the current
  screen; the library is untouched.
- **Settings**: account email and Sign Out; default subtitle language; Autoplay next
  episode; Refresh catalog (with last-updated time); Clear image cache; Erase My List
  and watch history (confirmed); app version.
- **Sign out** removes credentials and in-memory detail data. The library stays on the
  device; erasing it is the separate, explicit action above. *Claude's call.*

### States and errors

| Screen | Loading | Empty | Error |
|---|---|---|---|
| Home | snapshot, else skeleton shelves | n/a | full-screen Retry only when there is no cache |
| Shows / Movies | skeleton shelves | n/a | same as Home |
| Browse grid | skeleton tiles | Reset Filters | n/a (local) |
| Detail | catalog data + skeleton rows | "No episodes yet" | inline Retry in the right column; left column stays usable |
| Search | n/a (local) | "No results" | n/a |
| My List | n/a (local) | explanation + button | n/a |

## Motion & focus

### Tokens (in `OroroDesign.Motion`)

| Token | Value | Used for |
|---|---|---|
| focus | system | tile lift, parallax, button focus |
| `quick` | 0.2 s ease-out | text and badge swaps, image fade-in, footer strip |
| `standard` | spring, 0.45 s, slight bounce | hero dim and scroll to top, season switch, row expansion |
| `cinematic` | 0.6 s ease-in-out | backdrop crossfades, hero paging |
| `stagger` | 40 ms per item, max 5 items | shelves and rows entering |

No animation is written with ad-hoc durations; everything uses a token.

### Choreography

| Moment | Motion |
|---|---|
| Launch | backdrop fades in, hero text rises 24 pt and fades, shelves stagger in |
| Hero paging | the page strip slides (`cinematic`), backdrop and text together; a slow 1.00 → 1.06 scale drift on the backdrop over the 8 s dwell |
| Hero → shelves | the focus engine's scroll; the hero dims (`standard`) |
| Tile focus | system lift and parallax (`.buttonStyle(.card)`); title reveals below (`quick`) |
| Tile → Detail | zoom navigation transition from the tile **[spike]**. Fallback: detail backdrop crossfades in from the tile's image while the left column slides in 24 pt and fades, staggered |
| Detail data arrives | skeleton rows crossfade to real rows, staggered |
| Episode row focus | row expands to full plot (`standard`) |
| Season switch | list slides in the direction of the change and fades |
| + My List | symbol replace with a bounce |
| Play pressed | label morphs to a spinner in place; player fades in through black |
| Browse filter change | whole grid crossfades (`quick`); no per-cell layout animation |

**Reduce Motion**: every row above becomes a `quick` crossfade; no backdrop drift, no
hero auto-advance, no parallax.

### tvOS 26 look

- Tab bar: system (Liquid Glass comes for free).
- Buttons on the hero and Detail: glass button styles (prominent for Play). Season
  pills and filter chips: glass capsules. **[spike]** confirm hitch budget on the
  target device; fallback is a translucent material fill.
- Badges (IMDb, HD, CC) stay solid for legibility.
- No glass on scrolling tiles.

### Images

- Fade in on load; prefetch the next row via the Nuke prefetcher.
- Decode at the tile's pixel size (posters are 600×900; backdrops downsampled).
- Hero and Detail backdrops are prefetched before their transition starts, so a
  transition never lands on an empty frame.

### Performance budget

Device: Apple TV 4K (2nd gen). Measured with the Instruments Animation Hitches
template, release build.

- Hitch time ratio below 5 ms/s for: horizontal shelf traversal, vertical traversal of
  Home, hero collapse, tile → Detail and back, season switch, Browse grid traversal
  with 7,920 titles.
- Home first paint under 1 s from a warm cache; full catalog ready under 2.5 s.
- 10 minutes of continuous browsing without a memory termination.

### Accessibility

- VoiceOver labels on everything that is icon- or badge-only ("IMDb rating 8.3",
  "High definition", country names instead of flag emoji, "40 percent watched").
- A tile reads as one element: title, year, rating, progress.
- Reduce Motion as above; system text styles so Bold Text and contrast settings apply.

## iOS adaptation (basic)

Same features compile for iOS; layouts adapt via size classes: bottom tab bar, shorter
hero, detail split becomes stacked (info then episodes), long-press menus as context
menus. Native subtitle tracks work unchanged; with the overlay fallback the picker is
an on-screen menu. Trailers fall back to the `https://youtube.com/watch` URL.

Acceptance: on iPhone and iPad simulators the app signs in, browses every tab, opens
detail and plays with subtitles, with no clipped or overlapping layout.

## Testing

- **`swift test` (`OroroKit`)**: DTO decoding against fixtures, shelf building,
  filter/sort, search ranking, episode ordering and next-episode, Continue Watching
  and New Episodes rules (follow, detect, one-row-only, dismiss), progress thresholds, library pruning and size budget, synthetic playlist
  generation (or the VTT parser if the fallback is taken).
- **Simulator tests (`OroroUI`)**: view models, route handling, focus-memory fallbacks.
- SwiftUI previews with fake data for every key view; previews compile in CI. No
  snapshot-testing library.
- **Manual QA on Apple TV hardware** using the Phase 0 checklists and the performance
  budget, repeated at the end of every milestone that touches UI.

## Delivery

### Phase 0 — spike (throwaway code, real fixtures, real hardware)

| # | Question | Pass criteria | If it fails |
|---|---|---|---|
| S1 | Focus memory in SwiftUI | tile → Detail → Menu returns to the same tile, 20/20, including tiles scrolled far right; tab switch and back likewise | `UICollectionView`-backed shelves |
| S2 | Zoom transition on tvOS 26 | runs within the hitch budget, push and pop | specified crossfade fallback |
| S3 | Hero collapse and paging | within the hitch budget; paging does not fight button focus | simplify to crossfade collapse |
| S4 | Native subtitle injection | ±100 ms on three titles, survives seeking | overlay fallback |
| S5 | Browse grid with 7,920 posters | within the hitch budget | paged grid (200 per page) |
| S6 | `youtube://` on tvOS | opens the trailer | no Trailer button on tvOS |
| S7 | Glass controls | within the hitch budget | material fill |
| S8 | Library durability, `ETag` | survives reinstall and purge; conditional fetch works | keep design; full fetch |

Results are written into this spec (a "Spike results" section) before Milestone 1.

### Milestones

1. **Foundation** — packages, Tuist, API, Core, Store, fixtures script, CI.
2. **Design system, navigation, Home.**
3. **Shows / Movies, Browse, Search, My List.**
4. **Detail and Player.**
5. **Sign-in, Settings, error states, localisation, accessibility.**
6. **iOS adaptation, performance pass, old code removed, README rewritten.**

### Done means

- Every anti-goal has been checked on Apple TV hardware and none occurs.
- The performance budget is met and the numbers are recorded.
- CI is green; no credentials or account ids anywhere in the repo.
- The iOS acceptance check passes.

## Left to the builder

- Exact visual tokens (font sizes, spacing, colours) within the mockup look.
- Hero selection weighting and the Top Rated year threshold.
- Whether Features splits into per-feature modules.
- Top Shelf extension (nice-to-have; may follow later).
- Exact Tuist version and config layout.

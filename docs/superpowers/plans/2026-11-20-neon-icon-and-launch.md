# Neon Icon and Power-On Launch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the app icons (tvOS layered icon, App Store icon, Top Shelf, iOS) with the neon "ororo" wordmark, remove the launch flash, and turn the loading screen into a CRT "power-on" intro that overlaps real startup.

**Architecture:** One HTML/SVG page (`Branding/brand.html`) draws every artwork variant from URL parameters with a committed Nunito font; `Scripts/render-icons.sh` screenshots it with headless Chrome into the asset catalogs. A pure `LaunchGate` decides when the loading screen may leave; `AppRootView` keeps a single `LoadingScreen` across launching / catalog loading so the intro plays once.

**Tech Stack:** SwiftUI (tvOS 26 / iOS 26), Swift Testing, asset catalogs, headless Google Chrome, bash.

**Spec:** `docs/superpowers/specs/2026-11-20-neon-icon-and-launch-design.md`

## Global Constraints

- Amber `#FFB547` wordmark with a warm orange bloom; screen gradient radial `#2B1606` → `#060303`; faint horizontal scanlines.
- Typeface Nunito at weight 900 (SIL OFL), lowercase "ororo"; never Apple SF fonts in artwork.
- Sizes: tvOS icon layers 400×240 @1x and @2x; App Store icon layers 1280×768; Top Shelf 1920×720 and Top Shelf Wide 2320×720, each @1x and @2x; iOS 1024×1024.
- Launch screen background colour `#060303` (`LaunchBackground`) on both apps.
- Every animation uses a `Motion` token (no ad-hoc durations in views); Reduce Motion: wordmark fade-in only, no line or flicker.
- The intro never holds the loading screen after the intro has finished and the session has left `.launching`/`.loadingCatalog`.
- Strings are localised (en + ru) in `OroroFeatures/Resources/Localizable.xcstrings`; existing keys `appRoot.loading.catalog` / `appRoot.loading.launching` stay.

## Review Focus

- Catalog cached, session `.ready` before the intro ends → loading screen stays until the intro ends, then Home (Task 3 gate test `waitsForIntroWhenReadyEarly`).
- Signed out / failed during the intro → sign-in / error appear only after the intro (Task 3 gate tests `signedOutAfterIntro`, `failedAfterIntro`).
- First sign-in after the intro already played → catalog progress shows with a static wordmark, no replayed power-on (Task 3 test `introPlaysOnlyOnce` on `LaunchGate.playsIntro`).
- Remote press during the intro → skips straight to whatever the session allows (Task 3 gate test `skippedIntroCountsAsFinished`).
- Reduce Motion → intro shortened to a fade (Task 3 test `reduceMotionShortensIntro`).

---

### Task 1: Artwork pipeline and new icons

**Files:**
- Create: `Branding/brand.html`, `Branding/fonts/Nunito.ttf`, `Branding/fonts/OFL.txt`, `Scripts/render-icons.sh`
- Modify (regenerated PNGs, same filenames and `Contents.json` as today): everything under `Apps/TV/Assets.xcassets/App Icon & Top Shelf Image.brandassets/`, `Apps/iOS/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
- Create: `Packages/OroroUI/Sources/OroroFeatures/Resources/Brand.xcassets/Wordmark.imageset/` (`Contents.json`, `wordmark@1x.png`, `@2x`, `@3x`)
- Modify: spec "Artwork" bullet: font is loaded from the committed TTF via `@font-face` instead of outlined text.

**Interfaces:**
- Produces: image asset `Wordmark` in OroroFeatures' bundle (transparent, crisp amber "ororo" with tight glow, 600×200 pt); `Scripts/render-icons.sh` (no args; idempotent).

- [ ] **Step 1: Add the font.** Copy Nunito variable TTF and OFL from `github.com/google/fonts/raw/main/ofl/nunito/` into `Branding/fonts/`.
- [ ] **Step 2: Write `Branding/brand.html`.** Reads `?art=<icon|appstore|topshelf|topshelfwide|ios|wordmark>&layer=<back|middle|front|flat>&w=<px>&h=<px>`, sets `body` to exactly w×h, draws one SVG: `back` = screen gradient + vignette + scanlines; `middle` = amber bloom only (transparent elsewhere); `front` = crisp wordmark with tight glow (transparent elsewhere); `flat` = all three composited. Wordmark font size ≈ 0.2 × width for icons; Top Shelf art places the word left of centre at ≈ 0.09 × width; `wordmark` art is `front` on a transparent background. Font: `@font-face { font-family: Nunito; src: url(fonts/Nunito.ttf); font-weight: 200 1000 }`, weight 900.
- [ ] **Step 3: Write `Scripts/render-icons.sh`.** For each output, run headless Chrome (`--headless=new --hide-scrollbars --default-background-color=00000000 --window-size=W,H --force-device-scale-factor=S --screenshot=<path> file://…/brand.html?…`) and write straight into the asset catalog paths. Outputs: TV icon back/middle/front @1x (400×240) and @2x; App Store back/middle/front (1280×768); Top Shelf flat 1920×720 @1x/@2x; Top Shelf Wide flat 2320×720 @1x/@2x; iOS flat 1024×1024; Wordmark @1x/@2x/@3x of 600×200. Fail with a message if Chrome is missing. Back layers must be opaque (iOS icon too).
- [ ] **Step 4: Run it and check sizes.** Run `Scripts/render-icons.sh`, then `sips -g pixelWidth -g pixelHeight` on every output. Expected: each matches the table above (×2/×3 for scales).
- [ ] **Step 5: Look at the art.** Open the TV @1x front composited over back, the iOS icon and a Top Shelf image; the word must read clearly at 400×240 @1x (glow tighter than the brainstorm sketch).
- [ ] **Step 6: Build the TV app** (`xcodebuild build -workspace Ororo.xcworkspace -scheme OroroTV -destination 'generic/platform=tvOS Simulator'`) and expect no asset-catalog warnings about sizes.
- [ ] **Step 7: Commit** `feat(brand): neon wordmark icons, Top Shelf and render pipeline`.

### Task 2: Launch screen colour

**Files:**
- Create: `Apps/TV/Assets.xcassets/LaunchBackground.colorset/Contents.json`, `Apps/iOS/Assets.xcassets/LaunchBackground.colorset/Contents.json` (sRGB `#060303`, any appearance)
- Modify: `Apps/TV/Info.plist` (add), `Apps/iOS/Info.plist:35-36` (fill): `UILaunchScreen` = `{ UIColorName: LaunchBackground }`

- [ ] **Step 1:** Add the colour sets and the plist keys.
- [ ] **Step 2:** Build and launch on the tvOS simulator; take a screenshot within 0.3 s of `simctl launch`. Expected: the near-black warm screen, not white or grey.
- [ ] **Step 3: Commit** `feat(launch): launch screen matches the power-on's first frame`.

### Task 3: Power-on loading screen and launch gate

**Files:**
- Create: `Packages/OroroUI/Sources/OroroFeatures/AppRoot/LaunchGate.swift`
- Modify: `Packages/OroroUI/Sources/OroroFeatures/AppRoot/LoadingScreen.swift` (rebuild `LoadingScreen`), `Packages/OroroUI/Sources/OroroFeatures/AppRoot/AppRootView.swift` (root switch), `Packages/OroroUI/Sources/OroroDesign/Tokens/Motion.swift` (tokens)
- Test: `Packages/OroroUI/Tests/OroroFeaturesTests/LaunchGateTests.swift`, `Packages/OroroUI/Tests/OroroDesignTests/MotionTests.swift`

**Interfaces:**
- Consumes: `Wordmark` image (Task 1), `AppSession.State`.
- Produces:
  - `enum LaunchGate { static func showsLoading(_ state: AppSession.State, introFinished: Bool) -> Bool; static func playsIntro(introFinished: Bool) -> Bool; static func progress(_ state: AppSession.State) -> Double? }`
  - `Motion.powerOnLine: Animation` (`.easeOut(duration: 0.35)`), `Motion.powerOnOpen: Animation` (`.easeOut(duration: 0.3)`), `Motion.powerOnDuration(reduceMotion: Bool) -> Duration` (1.1 s; 0.2 s with Reduce Motion).
  - `LoadingScreen(progress: Double?, playsIntro: Bool, onIntroFinished: () -> Void)`

- [ ] **Step 1: Write the failing tests.**

```swift
@Suite struct LaunchGateTests {
    @Test func waitsForIntroWhenReadyEarly() {
        #expect(LaunchGate.showsLoading(.ready, introFinished: false))
        #expect(!LaunchGate.showsLoading(.ready, introFinished: true))
    }
    @Test func signedOutAfterIntro() {
        #expect(LaunchGate.showsLoading(.signedOut, introFinished: false))
        #expect(!LaunchGate.showsLoading(.signedOut, introFinished: true))
    }
    @Test func failedAfterIntro() {
        #expect(LaunchGate.showsLoading(.failed(.offline), introFinished: false))
        #expect(!LaunchGate.showsLoading(.failed(.offline), introFinished: true))
    }
    @Test func loadingStatesAlwaysShowLoading() {
        #expect(LaunchGate.showsLoading(.launching, introFinished: true))
        #expect(LaunchGate.showsLoading(.loadingCatalog(0.4), introFinished: true))
        #expect(LaunchGate.progress(.loadingCatalog(0.4)) == 0.4)
        #expect(LaunchGate.progress(.launching) == nil)
    }
    @Test func skippedIntroCountsAsFinished() {
        // A press marks the intro finished; the gate then follows the session alone.
        #expect(!LaunchGate.showsLoading(.ready, introFinished: true))
    }
    @Test func introPlaysOnlyOnce() {
        #expect(LaunchGate.playsIntro(introFinished: false))
        #expect(!LaunchGate.playsIntro(introFinished: true))
    }
}
```

In `MotionTests`: `reduceMotionShortensIntro` — `#expect(Motion.powerOnDuration(reduceMotion: false) == .milliseconds(1100))`, `#expect(Motion.powerOnDuration(reduceMotion: true) == .milliseconds(200))`.

- [ ] **Step 2: Run them** (`xcodebuild test -scheme OroroUI-Package -destination 'platform=tvOS Simulator,name=Apple TV 4K (4th generation)' -only-testing:OroroFeaturesTests/LaunchGateTests -only-testing:OroroDesignTests/MotionTests`). Expected: build failure, `LaunchGate` / `powerOnDuration` not found.
- [ ] **Step 3: Implement `LaunchGate` and the Motion tokens.** `showsLoading` is true for `.launching` and `.loadingCatalog`, otherwise `!introFinished`.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Rebuild `LoadingScreen`.** Warm screen background (same gradient as the icon) with a scanline overlay; the `Wordmark` image centred. When `playsIntro`: a 2 pt `#FFF3D6` line with amber glow grows to full width (`Motion.powerOnLine`), opens vertically and fades (`Motion.powerOnOpen`) while the wordmark scales from 5% height to full and unblurs, then two quick opacity dips (flicker) — then call `onIntroFinished` after `Motion.powerOnDuration(reduceMotion:)`. Reduce Motion: wordmark fades in, no line or flicker. Without `playsIntro`: wordmark shown at rest. When `progress` is non-nil: amber progress line (34% width, 4 pt, glow) at 68% height and the `appRoot.loading.catalog` caption below; accessibility label/value as today. Skip: tvOS `.focusable()` + `.onTapGesture` and `.onExitCommand`, iOS `.onTapGesture`, each calling `onIntroFinished` once.
- [ ] **Step 6: Wire `AppRootView`.** Add `@State private var introFinished = false`. In the root `ZStack`: if `LaunchGate.showsLoading(session.state, introFinished:)` show one `LoadingScreen(progress: LaunchGate.progress(session.state), playsIntro: LaunchGate.playsIntro(introFinished:), onIntroFinished: { introFinished = true })` (single identity, `.transition(.opacity)`), else the existing switch for `.signedOut`, `.ready`, `.failed`. Keep the crossfade keyed on what's shown.
- [ ] **Step 7: Run all OroroUI tests, the iOS build and `swiftlint lint --strict`.** Expected: all pass.
- [ ] **Step 8: Commit** `feat(launch): CRT power-on loading screen that overlaps startup`.

### Task 4: Verify on device and ship

- [ ] **Step 1:** On the tvOS simulator (signed in, cached catalog), screenshot at ~0.2 s, ~0.6 s and ~1.5 s after launch. Expected: dark screen → wordmark appearing → Home.
- [ ] **Step 2:** Confirm the built app carries the new icon: `xcrun assetutil --info <built .app>/Assets.car` lists the `App Icon` image stack with three layers and the Top Shelf images at the Task 1 sizes. (The home row itself is checked by eye on the TV after Step 3.)
- [ ] **Step 3:** Push the branch, open a PR, and run `Scripts/install-tv.sh`.

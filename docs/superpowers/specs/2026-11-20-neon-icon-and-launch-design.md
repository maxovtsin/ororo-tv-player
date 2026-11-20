# Neon icon and power-on launch

Date: 2026-11-20 · Status: draft for approval

## Why

The current icon (white ring + play triangle on a purple gradient) is generic: it says "video
app", not Ororo, and the tvOS parallax layers are just that ring floating over a gradient.
Opening the app shows a blank flash, then the word "Ororo" in system text with a spinner. Both
should feel like one brand.

## What was chosen

Picked in the visual companion from 10 directions, then 4 blends of the two favourites
(Wordmark + CRT glow):

- **App icon: the glowing CRT ring** (option 10): an orange (#FF9F1C) ring, slightly wider than tall,
  with a soft glow and scanlines running through it, on the warm tube screen. Chosen after the first
  install: the small icon should be the ring, the big Top Shelf banner the word.
- **Top Shelf and loading screen: Neon wordmark.** Lowercase "ororo", heavy and rounded, glowing amber (#FFB547 with a
  warm orange bloom) on a dark warm "tube screen" (radial #2B1606 → #060303) with faint
  horizontal scanlines.
- **Loading: the TV powers on.** Warm dark screen → a bright line snaps across and opens up →
  "ororo" flickers on in neon (≈1 s) → on first load only, a glowing amber progress line with
  "Loading the catalog…" → Home fades in.

## Goals

- One brand across the tvOS icon (all sizes, parallax), the App Store icon, Top Shelf, the iOS
  icon, the launch screen and the in-app loading screen.
- No blank flash at launch.
- The intro never makes a launch noticeably slower.

## Non-goals

- No change to the sign-in, error or Home screens beyond the transition from loading.
- No new brand colour system across the app (the amber stays in the icon and loading screen).

## Anti-goals

- An intro that delays Home by a full second on every launch.
- A glow so soft the name is unreadable at home-row size (the first sketch had this problem).
- Using Apple's SF fonts in the logo (their licence doesn't cover logos).

## Design

### Artwork (source of truth: SVG, rendered to PNG)

- `Branding/` holds the SVG sources and a render script (`Scripts/render-icons.sh`) that
  outputs every PNG the asset catalogs need using headless Chrome, so the icon can be
  regenerated after tweaks. Generated PNGs are committed.
- Typeface: **Nunito Black** (SIL Open Font License). The TTF and its licence are committed in
  `Branding/fonts/` and loaded via `@font-face`, so rendering never depends on installed fonts.
- tvOS icon layers (400×240 @1x/@2x and 1280×768 App Store):
  - Back: tube-screen gradient with a soft vignette and scanlines.
  - Middle: the amber bloom behind the word.
  - Front: the crisp "ororo" with a tight glow, so the name lifts off the glow when tilted.
- Top Shelf (1920×720) and Top Shelf Wide (2320×720): the same screen with the wordmark centred
  (≈0.11 × width), scanlines through the letters.
- iOS 1024×1024: the flattened icon, with the wordmark sized for the square.

### Launch screen (system)

- `UILaunchScreen` on both apps: background colour only (`LaunchBackground` colour asset,
  #060303), matching the first frame of the power-on so there's no flash or jump. tvOS gets
  the key added (it currently has none).

### Loading screen (in app)

- `LoadingScreen` is rebuilt as the power-on: line → open → neon wordmark with a brief
  flicker, then the progress line during a catalog download. The wordmark is an image asset
  rendered from the same SVG (not system text) so it matches the icon exactly.
- **Timing (overlap):** the intro starts at launch and runs alongside the real startup
  (`session.state == .launching`). `AppRootView` leaves the loading screen once both the
  intro has finished and the session is past `.launching`. A remote press (select or
  Menu) or a tap on iOS skips the rest of the intro.
- Reduce Motion: no line or flicker, just a fade-in of the wordmark.
- VoiceOver: "Loading" / "Loading the catalog, 40 percent", as today.

## Approaches considered

- **SVG + render script (chosen):** reproducible, easy to tweak, sources reviewable in git.
- Drawing the icon in SwiftUI and exporting it with `ImageRenderer`: keeps it in Swift, but
  SVG filters (glow, scanlines) are clumsy to match and the export needs a harness.
- Hand-made PNGs from a design tool: best control, but nothing regenerable in the repo.

## Left to the builder

- Exact glow radii, scanline opacity and timings within the sketch's feel; check legibility
  at tvOS home-row size (the 400×240 @1x layer) before finishing.
- The render script's tooling, as long as it runs with what's on the Mac (Chrome headless,
  Python). The text is not outlined: the page loads the committed TTF via `@font-face`.
- Tests: the intro-and-session gating rule in `AppRootView` (when the loading screen may leave)
  is unit-tested; the artwork is checked by eye on the simulator and the TV.

# Ororo

A SwiftUI client for [ororo.tv](https://ororo.tv/en) on Apple TV (primary) and iPhone / iPad. It needs an ororo.tv
account. The old 2018 UIKit app was replaced wholesale; its history is in git.

The code is two Swift packages and two thin app targets:

- `Packages/OroroKit`: `OroroCore` (models, playback logic), `OroroAPI` (networking), `OroroStore` (library, catalog cache, Keychain).
- `Packages/OroroUI`: `OroroDesign` (components, image cache) and `OroroFeatures` (screens and view models).
- `Apps/TV` and `Apps/iOS`: the `@main` apps. `Project.swift` is the Tuist manifest; the Xcode project is generated, not committed.

## Prerequisites

- macOS with Xcode 27 (deployment targets are tvOS 26 and iOS 26).
- [Homebrew](https://brew.sh), then `brew install mise swiftlint`.
- Tuist is pinned in `.mise.toml` and run through mise; nothing else to install.

## Build

```sh
mise install                    # first time only: installs the pinned Tuist
mise exec -- tuist generate     # creates and opens Ororo.xcworkspace
```

Pick the `OroroTV` scheme (Apple TV) or `Ororo` (iPhone / iPad) and run.

## Tests and lint

```sh
swift test --package-path Packages/OroroKit
cd Packages/OroroUI && xcodebuild test -scheme OroroUI-Package \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (4th generation)'
cd Packages/OroroUI && xcodebuild build -scheme OroroUI-Package -destination 'generic/platform=iOS Simulator'
swiftlint lint --strict
```

Add `-only-testing:OroroFeaturesTests/<Suite>` (or `OroroDesignTests/<Suite>`) to run one UI suite, or
`--filter <Suite>` to `swift test`.

## Installing on your Apple TV

The team id (`FYCJCMJ4B5`, a free Apple developer account) is set in `Project.swift`.

1. Put the Apple TV and the Mac on the same Wi-Fi network.
2. On the Apple TV open Settings > Remotes and Devices > Remote App and Devices. In Xcode open Window > Devices and
   Simulators, pick the Apple TV under Discovered and enter the pairing code shown on the TV. (`xcrun devicectl list devices`
   shows it once paired.)
3. In Xcode choose the `OroroTV` scheme, select the Apple TV as the destination and press Run.

A free account signs builds for 7 days. After that the app stops launching: run it from Xcode again, installing over
the top. Your library (favourites, watch progress) survives that reinstall. Deleting the app from the Apple TV erases it.

## Re-recording API fixtures

Test fixtures live in `Packages/OroroKit/Tests/OroroTestSupport/Fixtures`. To refresh them from the live API:

```sh
ORORO_EMAIL=you@example.com ORORO_PASSWORD=... Scripts/record-fixtures.sh
```

The script trims and scrubs the responses. Never commit raw recordings or credentials.

## Notes

On first launch the app deletes data left by the 2018 version (its Core Data store and offline downloads).
There are no custom app icons or Top Shelf images yet; the legacy asset catalog held only empty slots, no image files.

## License

MIT, as in the original project.

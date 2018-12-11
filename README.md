[![Build Status][build-badge]][build-url]
[![Swift][swift-badge]][swift-url]
[![Platform][platform-badge]][platform-url]
[![License][mit-badge]][mit-url]


#  Ororo.tv Player

The unofficial video player to watch [Ororo.tv](https://ororo.tv/en) on iOS and tvOS. 
Written in pure Swift without external dependencies.

## Usage

1) Clone the repo `git clone git@github.com:dissimiral/ororo-tv-player.git`.
2) Open `Ororo-Player.xcworkspace`.
3) Replace credentials in `RootFlow` with your ones.
4) Chose the scheme either `iOS` or `tvOS`
5) Build it.

## Features

- [x] Movies and Shows.
- [x] Subtitles.
- [x] Search through movies and series.
- [x] Live Streaming.
- [x] Downloads are available on iOS.
- [x] Favorites are available on tvOS.
- [x] Resume playing from the point where you stopped.

- [ ] To implement subtitle languages picker.
- [ ] To implement Sign In screen.
- [ ] To implement a queue for episodes.
- [ ] To extend `GenericCollectionViewDataSource` to work with different kinds of cells on the same screen.

License
-------

**Ororo.tv Player** is released under the MIT license.

[build-badge]: https://travis-ci.org/dissimiral/ororo-tv-player.svg?branch=master
[build-url]: https://travis-ci.org/dissimiral/ororo-tv-player
[swift-badge]: https://img.shields.io/badge/swift-4.2-orange.svg?style=flat
[swift-url]: https://swift.org
[platform-badge]: https://img.shields.io/badge/platform-ios%20%7C%20tvos-lightgrey.svg
[platform-url]: https://swift.org
[mit-badge]: https://img.shields.io/badge/License-MIT-blue.svg?style=flat
[mit-url]: https://tldrlegal.com/license/mit-license

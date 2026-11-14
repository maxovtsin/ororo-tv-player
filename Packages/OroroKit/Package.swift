// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "OroroKit",
    platforms: [
        .tvOS(.v26),
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "OroroCore", targets: ["OroroCore"]),
        .library(name: "OroroAPI", targets: ["OroroAPI"]),
        .library(name: "OroroStore", targets: ["OroroStore"]),
        .library(name: "OroroTestSupport", targets: ["OroroTestSupport"])
    ],
    targets: [
        .target(name: "OroroCore"),
        .target(name: "OroroAPI", dependencies: ["OroroCore"]),
        .target(name: "OroroStore", dependencies: ["OroroAPI", "OroroCore"]),
        .target(
            name: "OroroTestSupport",
            dependencies: ["OroroCore"],
            path: "Tests/OroroTestSupport",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "OroroCoreTests", dependencies: ["OroroCore", "OroroTestSupport"]),
        .testTarget(name: "OroroAPITests", dependencies: ["OroroAPI", "OroroCore", "OroroTestSupport"]),
        .testTarget(name: "OroroStoreTests", dependencies: ["OroroStore", "OroroAPI", "OroroCore", "OroroTestSupport"])
    ],
    swiftLanguageModes: [.v6]
)

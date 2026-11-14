// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "OroroUI",
    defaultLocalization: "en",
    platforms: [
        .tvOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(name: "OroroDesign", targets: ["OroroDesign"]),
        .library(name: "OroroFeatures", targets: ["OroroFeatures"])
    ],
    dependencies: [
        .package(path: "../OroroKit"),
        .package(url: "https://github.com/kean/Nuke.git", from: "13.2.3")
    ],
    targets: [
        .target(
            name: "OroroDesign",
            dependencies: [
                .product(name: "Nuke", package: "Nuke"),
                .product(name: "NukeUI", package: "Nuke")
            ],
            resources: [.process("Resources")]
        ),
        .target(
            name: "OroroFeatures",
            dependencies: [
                "OroroDesign",
                .product(name: "OroroCore", package: "OroroKit"),
                .product(name: "OroroStore", package: "OroroKit"),
                .product(name: "OroroAPI", package: "OroroKit")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "OroroDesignTests",
            dependencies: [
                "OroroDesign",
                .product(name: "OroroTestSupport", package: "OroroKit")
            ]
        ),
        .testTarget(
            name: "OroroFeaturesTests",
            dependencies: [
                "OroroFeatures",
                .product(name: "OroroTestSupport", package: "OroroKit")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)

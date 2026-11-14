import ProjectDescription

let bundleID = "com.dissimirall.Ororo-Player"

let baseSettings: SettingsDictionary = [
    "DEVELOPMENT_TEAM": "FYCJCMJ4B5",
    "CODE_SIGN_STYLE": "Automatic",
    "SWIFT_VERSION": "6.0"
]

let project = Project(
    name: "Ororo",
    packages: [
        .package(path: "Packages/OroroUI")
    ],
    settings: .settings(base: baseSettings),
    targets: [
        .target(
            name: "OroroTV",
            destinations: [.appleTv],
            product: .app,
            bundleId: bundleID,
            deploymentTargets: .tvOS("26.0"),
            infoPlist: .file(path: "Apps/TV/Info.plist"),
            sources: ["Apps/TV/**/*.swift"],
            resources: ["Apps/TV/Assets.xcassets"],
            dependencies: [
                .package(product: "OroroFeatures")
            ],
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_APPICON_NAME": "App Icon & Top Shelf Image",
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": ""
            ])
        ),
        .target(
            name: "Ororo",
            destinations: [.iPhone, .iPad],
            product: .app,
            bundleId: bundleID,
            deploymentTargets: .iOS("26.0"),
            infoPlist: .file(path: "Apps/iOS/Info.plist"),
            sources: ["Apps/iOS/**/*.swift"],
            resources: ["Apps/iOS/Assets.xcassets"],
            dependencies: [
                .package(product: "OroroFeatures")
            ],
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": ""
            ])
        )
    ]
)

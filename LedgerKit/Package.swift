// swift-tools-version: 6.2
// The one local package that holds every line of product code (architecture §2).
// App targets link only the umbrella products LedgerAppKit / LedgerWatchAppKit.
// The target table below IS the dependency diagram in architecture §3 — changing
// an edge needs an ADR, and scripts/check-package-graph.sh fails if this file and
// LedgerKit/package-graph.expected.txt disagree.

import PackageDescription

// Strict concurrency is implied by `swiftLanguageModes: [.v6]`; warnings become
// errors via SWIFT_TREAT_WARNINGS_AS_ERRORS in Config/Base.xcconfig (unsafeFlags
// would make the package unconsumable).
let uiSettings: [SwiftSetting] = [.defaultIsolation(MainActor.self)]
let coreSettings: [SwiftSetting] = [.defaultIsolation(nil)]

let dependenciesProduct: Target.Dependency = .product(name: "Dependencies", package: "swift-dependencies")
let grdbProduct: Target.Dependency = .product(name: "GRDB", package: "GRDB.swift")
let snapshotProduct: Target.Dependency = .product(name: "SnapshotTesting", package: "swift-snapshot-testing")

/// Every feature module depends on the same spine (F00 target table).
let featureSpine: [Target.Dependency] = [
    "LedgerDomain",
    "LedgerDesign",
    "LedgerDependencies",
    "LedgerTestSupport",
    dependenciesProduct
]

let iOSFeatures = [
    "FeatureOnboarding",
    "FeatureToday",
    "FeatureProgram",
    "FeatureLibrary",
    "FeatureHistory",
    "FeatureSettings"
]

/// One test target per source target, except the two test-only helpers.
let testedTargets: [(name: String, settings: [SwiftSetting])] =
    [
        ("LedgerDomain", coreSettings),
        ("LedgerDependencies", coreSettings),
        ("LedgerPersistence", coreSettings),
        ("LedgerHealth", coreSettings),
        ("LedgerSync", coreSettings),
        ("LedgerActivityKit", coreSettings),
        ("LedgerDesign", uiSettings)
    ]
    + iOSFeatures.map { ($0, uiSettings) }
    + [
        ("FeatureWorkout", uiSettings),
        ("WatchFeatureWorkout", uiSettings),
        ("LedgerAppKit", uiSettings),
        ("LedgerWatchAppKit", uiSettings)
    ]

/// Test targets whose suites commit `__Snapshots__` references; SwiftPM must not treat those
/// PNGs as sources. Add a target here with its first snapshot suite.
let snapshotTestTargets: Set<String> = ["LedgerDesign"]

/// Test targets that read committed fixtures through `Bundle.module` (F05: `schema-v001.sql`).
let testResources: [String: [Resource]] = ["LedgerPersistence": [.copy("Fixtures")]]

let package = Package(
    name: "LedgerKit",
    platforms: [
        // macOS is present only so `swift test` can run the pure targets on the
        // host; every Apple-framework import outside Domain is behind #if canImport.
        .iOS(.v26),
        .watchOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "LedgerAppKit", targets: ["LedgerAppKit"]),
        .library(name: "LedgerWatchAppKit", targets: ["LedgerWatchAppKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", .upToNextMinor(from: "7.11.1")),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", .upToNextMinor(from: "1.17.0")),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", .upToNextMinor(from: "1.19.5"))
    ],
    targets: [
        // ---- core -----------------------------------------------------------
        .target(
            name: "LedgerDomain",
            resources: [.copy("Resources/exercises.json")],
            swiftSettings: coreSettings
        ),
        .target(
            name: "LedgerDependencies",
            dependencies: ["LedgerDomain", dependenciesProduct],
            swiftSettings: coreSettings
        ),
        .target(
            name: "LedgerPersistence",
            dependencies: ["LedgerDomain", grdbProduct],
            swiftSettings: coreSettings
        ),
        .target(name: "LedgerHealth", dependencies: ["LedgerDomain"], swiftSettings: coreSettings),
        .target(name: "LedgerSync", dependencies: ["LedgerDomain"], swiftSettings: coreSettings),
        .target(name: "LedgerActivityKit", dependencies: ["LedgerDomain"], swiftSettings: coreSettings),

        // ---- design ---------------------------------------------------------
        // Archivo ships inside LedgerDesign so previews, package tests and both apps load
        // the same file; the apps' UIAppFonts point into this target's resource bundle (F06).
        .target(
            name: "LedgerDesign",
            resources: [.copy("Resources/Archivo[wdth,wght].ttf"), .copy("Resources/OFL.txt")],
            swiftSettings: uiSettings
        ),

        // ---- features -------------------------------------------------------
        .target(name: "FeatureOnboarding", dependencies: featureSpine, swiftSettings: uiSettings),
        .target(name: "FeatureToday", dependencies: featureSpine, swiftSettings: uiSettings),
        .target(name: "FeatureProgram", dependencies: featureSpine, swiftSettings: uiSettings),
        .target(name: "FeatureLibrary", dependencies: featureSpine, swiftSettings: uiSettings),
        .target(name: "FeatureHistory", dependencies: featureSpine, swiftSettings: uiSettings),
        .target(name: "FeatureSettings", dependencies: featureSpine, swiftSettings: uiSettings),
        .target(
            name: "FeatureWorkout",
            dependencies: featureSpine + ["LedgerActivityKit"],
            swiftSettings: uiSettings
        ),
        .target(name: "WatchFeatureWorkout", dependencies: featureSpine, swiftSettings: uiSettings),

        // ---- test-only helpers (never linked by an app target) ---------------
        .target(
            name: "LedgerTestSupport",
            dependencies: [
                "LedgerDomain",
                "LedgerDependencies",
                "LedgerPersistence",
                "LedgerHealth",
                "LedgerSync",
                "LedgerDesign",
                dependenciesProduct
            ],
            swiftSettings: coreSettings
        ),
        .target(
            name: "LedgerSnapshotTesting",
            dependencies: ["LedgerTestSupport", snapshotProduct],
            swiftSettings: uiSettings
        ),

        // ---- umbrellas (the app targets' only link dependency) ---------------
        .target(
            name: "LedgerAppKit",
            dependencies: iOSFeatures.map { Target.Dependency.target(name: $0) } + [
                "FeatureWorkout",
                "LedgerDomain",
                "LedgerDependencies",
                "LedgerPersistence",
                "LedgerHealth",
                "LedgerSync",
                "LedgerDesign",
                "LedgerActivityKit",
                dependenciesProduct
            ],
            swiftSettings: uiSettings
        ),
        .target(
            name: "LedgerWatchAppKit",
            dependencies: [
                "WatchFeatureWorkout",
                "LedgerDomain",
                "LedgerDependencies",
                "LedgerPersistence",
                "LedgerHealth",
                "LedgerSync",
                "LedgerDesign",
                dependenciesProduct
            ],
            swiftSettings: uiSettings
        )
    ] + testedTargets.map { target in
        .testTarget(
            name: "\(target.name)Tests",
            dependencies: [
                .target(name: target.name),
                "LedgerTestSupport",
                "LedgerSnapshotTesting"
            ],
            exclude: snapshotTestTargets.contains(target.name) ? ["__Snapshots__"] : [],
            resources: testResources[target.name],
            swiftSettings: target.settings
        )
    }
)

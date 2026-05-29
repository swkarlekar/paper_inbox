// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PaperInbox",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PaperInbox", targets: ["PaperInbox"]),
        .library(name: "PaperInboxCore", targets: ["PaperInboxCore"])
    ],
    targets: [
        .target(
            name: "SQLiteShim",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "PaperInboxCore",
            dependencies: ["SQLiteShim"]
        ),
        .executableTarget(
            name: "PaperInbox",
            dependencies: ["PaperInboxCore"],
            linkerSettings: [
                .linkedFramework("WebKit")
            ]
        ),
        .testTarget(
            name: "PaperInboxCoreTests",
            dependencies: ["PaperInboxCore"]
        )
    ]
)

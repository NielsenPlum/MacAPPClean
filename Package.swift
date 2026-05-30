// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MacAppClean",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacAppClean", targets: ["MacAppClean"])
    ],
    targets: [
        .executableTarget(
            name: "MacAppClean",
            path: "Sources/MacAppClean",
            exclude: ["Resources", "Assets.xcassets"]
        )
    ]
)

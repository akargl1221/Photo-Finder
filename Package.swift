// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PersonFinderApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "PersonFinderApp",
            targets: ["PersonFinderApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "PersonFinderApp",
            path: "Sources/PersonFinderApp"
        )
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GengarileoAssistant",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "GengarileoAssistant",
            targets: ["GengarileoAssistant"]
        )
    ],
    targets: [
        .executableTarget(
            name: "GengarileoAssistant",
            path: "Sources/GengarileoAssistant"
        )
    ]
)

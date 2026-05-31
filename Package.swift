// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "TelegramVPN",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "TelegramVPN",
            targets: ["TelegramVPN"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "TelegramVPN",
            dependencies: [],
            path: "Sources/TelegramVPN",
            resources: [.copy("Resources")]
        )
    ]
)

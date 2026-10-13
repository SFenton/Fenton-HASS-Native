// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FentonHomeApple",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "HassTelemetry", targets: ["HassTelemetry"]),
        .library(name: "HassCore", targets: ["HassCore"]),
        .library(name: "HassDesign", targets: ["HassDesign"]),
        .library(name: "HassUI", targets: ["HassUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/home-assistant/HAKit", from: "0.4.9"),
        // Prebuilt Google WebRTC for live camera video (go2rtc); iOS only so `swift test` on macOS skips it.
        .package(url: "https://github.com/stasel/WebRTC", from: "137.0.0"),
    ],
    targets: [
        // Signposts and the in-app performance log; every other module reports into it.
        .target(name: "HassTelemetry"),
        .target(
            name: "HassCore",
            dependencies: ["HassTelemetry", .product(name: "HAKit", package: "HAKit")]
        ),
        .target(name: "HassDesign", dependencies: ["HassTelemetry"]),
        .target(
            name: "HassUI",
            dependencies: [
                "HassCore",
                "HassDesign",
                "HassTelemetry",
                .product(name: "WebRTC", package: "WebRTC", condition: .when(platforms: [.iOS])),
            ]
        ),
        .testTarget(
            name: "HassCoreTests",
            dependencies: ["HassCore", .product(name: "HAKit+Mocks", package: "HAKit")]
        ),
        .testTarget(name: "HassDesignTests", dependencies: ["HassDesign"]),
        .testTarget(name: "HassTelemetryTests", dependencies: ["HassTelemetry"]),
        .testTarget(
            name: "HassUITests",
            dependencies: ["HassUI", "HassCore", .product(name: "HAKit+Mocks", package: "HAKit")]
        ),
    ],
    swiftLanguageModes: [.v6]
)

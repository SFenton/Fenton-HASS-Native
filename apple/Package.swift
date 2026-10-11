// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FentonHomeApple",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
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
        .target(
            name: "HassCore",
            dependencies: [.product(name: "HAKit", package: "HAKit")]
        ),
        .target(name: "HassDesign"),
        .target(
            name: "HassUI",
            dependencies: [
                "HassCore",
                "HassDesign",
                .product(name: "WebRTC", package: "WebRTC", condition: .when(platforms: [.iOS])),
            ]
        ),
        .testTarget(name: "HassCoreTests", dependencies: ["HassCore"]),
        .testTarget(name: "HassDesignTests", dependencies: ["HassDesign"]),
        .testTarget(name: "HassUITests", dependencies: ["HassUI", "HassCore"]),
    ],
    swiftLanguageModes: [.v6]
)

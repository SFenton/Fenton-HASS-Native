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
    ],
    targets: [
        .target(
            name: "HassCore",
            dependencies: [.product(name: "HAKit", package: "HAKit")]
        ),
        .target(name: "HassDesign"),
        .target(name: "HassUI", dependencies: ["HassCore", "HassDesign"]),
        .testTarget(
            name: "HassCoreTests",
            dependencies: ["HassCore", .product(name: "HAKit+Mocks", package: "HAKit")]
        ),
        .testTarget(name: "HassDesignTests", dependencies: ["HassDesign"]),
        .testTarget(
            name: "HassUITests",
            dependencies: ["HassUI", "HassCore", .product(name: "HAKit+Mocks", package: "HAKit")]
        ),
    ],
    swiftLanguageModes: [.v6]
)

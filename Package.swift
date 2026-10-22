// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BKAppSwitch",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "BKAppSwitch", targets: ["BKAppSwitch"])],
    targets: [
        .target(name: "AppSwitchCore"),
        .executableTarget(name: "BKAppSwitch", dependencies: ["AppSwitchCore"]),
        .testTarget(name: "AppSwitchCoreTests", dependencies: ["AppSwitchCore"])
    ]
)

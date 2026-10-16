// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppSwitch",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "AppSwitch", targets: ["AppSwitch"])],
    targets: [
        .target(name: "AppSwitchCore"),
        .executableTarget(name: "AppSwitch", dependencies: ["AppSwitchCore"]),
        .testTarget(name: "AppSwitchCoreTests", dependencies: ["AppSwitchCore"])
    ]
)

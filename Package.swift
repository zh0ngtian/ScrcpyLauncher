// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScrcpyLauncher",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ScrcpyLauncher", targets: ["ScrcpyLauncher"])],
    targets: [
        .target(name: "ScrcpyLauncherCore"),
        .executableTarget(name: "ScrcpyLauncher", dependencies: ["ScrcpyLauncherCore"]),
        .testTarget(name: "ScrcpyLauncherCoreTests", dependencies: ["ScrcpyLauncherCore"]),
    ]
)

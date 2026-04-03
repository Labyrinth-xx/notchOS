// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchConsole",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchConsole",
            path: "Sources/NotchConsole",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
            ]
        )
    ]
)

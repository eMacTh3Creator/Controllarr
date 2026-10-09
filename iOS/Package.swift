// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ControllarrRemoteProtocol",
    platforms: [.macOS(.v15), .iOS(.v17)],
    targets: [
        .target(name: "ControllarrRemoteProtocol", path: "Sources",
                exclude: ["ControllarrRemoteApp.swift", "Discovery.swift", "RemoteModel.swift", "Views.swift", "AdaptiveViews.swift", "PlatformViews.swift", "LayoutPreview.swift", "Assets.xcassets"],
                sources: ["RemoteAPI.swift", "Workspace.swift"]),
        .testTarget(name: "RemoteProtocolTests", dependencies: ["ControllarrRemoteProtocol"], path: "Tests")
    ]
)

#!/usr/bin/env swift
import Foundation
import ImageIO

func require(_ condition: Bool, _ message: String) {
    guard condition else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

let args = CommandLine.arguments
require(args.count == 2, "usage: check-release.swift <ControllarrRemote.app>")
let app = URL(fileURLWithPath: args[1], isDirectory: true)
let data = try Data(contentsOf: app.appendingPathComponent("Info.plist"))
let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
require(info["CFBundleIdentifier"] as? String == "com.controllarr.remote", "unexpected bundle identifier")
require((info["DTSDKName"] as? String)?.hasPrefix("iphoneos") == true, "a device archive is required")
require(Set(info["UIDeviceFamily"] as? [Int] ?? []) == [1, 2], "iPhone and iPad support must be retained")
let orientations = Set(info["UISupportedInterfaceOrientations~ipad"] as? [String]
    ?? info["UISupportedInterfaceOrientations"] as? [String] ?? [])
require(orientations == Set([
    "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
    "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"
]), "all four iPad orientations are required for multitasking")
require((info["UILaunchScreen"] as? [String: Any]) != nil, "launch screen declaration is required")
require(info["UIRequiresFullScreen"] as? Bool != true, "do not disable iPad multitasking to bypass validation")

let script = URL(fileURLWithPath: #filePath).standardizedFileURL
let root = script.deletingLastPathComponent().deletingLastPathComponent()
let icon = root.appendingPathComponent("Sources/Assets.xcassets/AppIcon.appiconset/icon.png")
guard let source = CGImageSourceCreateWithURL(icon as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    require(false, "could not decode the marketing icon")
    exit(1)
}
require(image.width == 1024 && image.height == 1024, "marketing icon must be 1024 x 1024")
require([.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo), "marketing icon must not contain an alpha channel")
let compiledIcons = try FileManager.default.contentsOfDirectory(at: app, includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.hasPrefix("AppIcon") && $0.pathExtension == "png" }
require(!compiledIcons.isEmpty, "compiled app icons are missing")
for icon in compiledIcons {
    guard let source = CGImageSourceCreateWithURL(icon as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        require(false, "could not decode \(icon.lastPathComponent)")
        continue
    }
    require([.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo), "\(icon.lastPathComponent) contains alpha")
}
print("PASS: device bundle, iPad orientations, launch screen and opaque app icons")
print("Built with Xcode \(info["DTXcode"] ?? "unknown") (\(info["DTXcodeBuild"] ?? "unknown")), SDK \(info["DTSDKName"] ?? "unknown").")
print("Confirm this Xcode/SDK is supported by App Store Connect; local checks do not prove Apple acceptance.")

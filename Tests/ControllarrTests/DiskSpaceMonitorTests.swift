//
//  DiskSpaceMonitorTests.swift
//  ControllarrTests
//

import Testing
import Foundation
@testable import Services
@testable import Persistence

@Test func testDiskSpaceStatusDefaults() {
    let status = DiskSpaceMonitor.Status(
        freeBytes: 50_000_000_000,
        thresholdBytes: 10_000_000_000,
        isPaused: false,
        pausedHashes: []
    )
    #expect(status.freeBytes == 50_000_000_000)
    #expect(status.thresholdBytes == 10_000_000_000)
    #expect(status.isPaused == false)
    #expect(status.pausedHashes.isEmpty)
}

@Test func testDiskSpaceStatusPausedState() {
    let hashes: Set<String> = ["abc123", "def456"]
    let status = DiskSpaceMonitor.Status(
        freeBytes: 1_000_000_000,
        thresholdBytes: 10_000_000_000,
        isPaused: true,
        pausedHashes: hashes
    )
    #expect(status.freeBytes == 1_000_000_000)
    #expect(status.thresholdBytes == 10_000_000_000)
    #expect(status.isPaused == true)
    #expect(status.pausedHashes.count == 2)
    #expect(status.pausedHashes.contains("abc123"))
    #expect(status.pausedHashes.contains("def456"))
}

@Test func testDiskSpaceSettingsDefaults() {
    let home = URL(fileURLWithPath: "/tmp/controllarr-test-home")
    let s = Settings.defaults(homeDir: home)
    #expect(s.diskSpaceMinimumGB == nil)
    #expect(s.diskSpaceMonitorPath.isEmpty)
}

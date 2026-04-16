//
//  PersistenceTests.swift
//  ControllarrTests
//

import Testing
import Foundation
@testable import Persistence

// MARK: - Settings

@Test func testSettingsDefaults() {
    let home = URL(fileURLWithPath: "/tmp/controllarr-test-home")
    let s = Settings.defaults(homeDir: home)
    #expect(s.listenPortRangeStart > 0)
    #expect(s.listenPortRangeEnd > s.listenPortRangeStart)
    #expect(s.webUIPort > 0)
    #expect(s.stallThresholdMinutes > 0)
    #expect(!s.defaultSavePath.isEmpty)
    #expect(!s.webUIHost.isEmpty)
    #expect(!s.webUIUsername.isEmpty)
    #expect(!s.webUIPassword.isEmpty)
    #expect(s.seedLimitAction == .pause)
    #expect(s.minimumSeedTimeMinutes == 60)
    #expect(s.healthStallMinutes == 30)
    #expect(s.healthReannounceOnStall == true)
    #expect(s.globalMaxRatio == nil)
    #expect(s.globalMaxSeedingTimeMinutes == nil)
    #expect(s.bandwidthSchedule.isEmpty)
    #expect(s.diskSpaceMinimumGB == nil)
    #expect(s.diskSpaceMonitorPath.isEmpty)
    #expect(s.arrEndpoints.isEmpty)
    #expect(s.arrReSearchAfterHours == 6)
}

@Test func testV1SettingsDecoding() throws {
    let json = """
    {
        "listenPortRangeStart": 49152,
        "listenPortRangeEnd": 65000,
        "stallThresholdMinutes": 10,
        "defaultSavePath": "/tmp/downloads",
        "webUIHost": "127.0.0.1",
        "webUIPort": 8791,
        "webUIUsername": "admin",
        "webUIPassword": "adminadmin"
    }
    """
    let data = Data(json.utf8)
    let s = try JSONDecoder().decode(Settings.self, from: data)
    #expect(s.listenPortRangeStart == 49152)
    #expect(s.listenPortRangeEnd == 65000)
    #expect(s.stallThresholdMinutes == 10)
    #expect(s.defaultSavePath == "/tmp/downloads")
    #expect(s.webUIHost == "127.0.0.1")
    #expect(s.webUIPort == 8791)
    #expect(s.webUIUsername == "admin")
    #expect(s.webUIPassword == "adminadmin")
    // New fields should have their defaults:
    #expect(s.seedLimitAction == .pause)
    #expect(s.minimumSeedTimeMinutes == 60)
    #expect(s.healthStallMinutes == 30)
    #expect(s.healthReannounceOnStall == true)
    #expect(s.globalMaxRatio == nil)
    #expect(s.globalMaxSeedingTimeMinutes == nil)
    #expect(s.bandwidthSchedule.isEmpty)
    #expect(s.diskSpaceMinimumGB == nil)
    #expect(s.diskSpaceMonitorPath.isEmpty)
    #expect(s.arrEndpoints.isEmpty)
    #expect(s.arrReSearchAfterHours == 6)
}

@Test func testSettingsRoundTrip() throws {
    let rule = BandwidthRule(
        name: "Weekday daytime",
        enabled: true,
        daysOfWeek: [2, 3, 4, 5, 6],
        startHour: 8,
        startMinute: 0,
        endHour: 17,
        endMinute: 0,
        maxDownloadKBps: 5000,
        maxUploadKBps: 1000
    )
    let original = Settings(
        listenPortRangeStart: 50000,
        listenPortRangeEnd: 60000,
        stallThresholdMinutes: 15,
        defaultSavePath: "/tmp/test-save",
        webUIHost: "0.0.0.0",
        webUIPort: 9090,
        webUIUsername: "user",
        webUIPassword: "pass",
        globalMaxRatio: 2.0,
        globalMaxSeedingTimeMinutes: 1440,
        seedLimitAction: .removeKeepFiles,
        minimumSeedTimeMinutes: 120,
        healthStallMinutes: 45,
        healthReannounceOnStall: false,
        bandwidthSchedule: [rule]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(Settings.self, from: data)
    #expect(decoded == original)
}

// MARK: - Category

@Test func testCategoryRoundTrip() throws {
    let original = Category(
        name: "Movies",
        savePath: "/tmp/movies",
        completePath: "/media/movies",
        extractArchives: true,
        blockedExtensions: ["exe", "bat"],
        maxRatio: 2.5,
        maxSeedingTimeMinutes: 4320
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(Category.self, from: data)
    #expect(decoded == original)
}

@Test func testV1CategoryDecoding() throws {
    let json = """
    {
        "name": "TV",
        "savePath": "/tmp/tv"
    }
    """
    let data = Data(json.utf8)
    let cat = try JSONDecoder().decode(Category.self, from: data)
    #expect(cat.name == "TV")
    #expect(cat.savePath == "/tmp/tv")
    #expect(cat.completePath == nil)
    #expect(cat.extractArchives == false)
    #expect(cat.blockedExtensions.isEmpty)
    #expect(cat.maxRatio == nil)
    #expect(cat.maxSeedingTimeMinutes == nil)
    #expect(cat.dangerousPatterns.isEmpty)
}

// MARK: - BandwidthRule

@Test func testBandwidthRuleRoundTrip() throws {
    let original = BandwidthRule(
        name: "Night owl",
        enabled: true,
        daysOfWeek: [1, 7],
        startHour: 22,
        startMinute: 30,
        endHour: 6,
        endMinute: 0,
        maxDownloadKBps: 10000,
        maxUploadKBps: 2000
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(BandwidthRule.self, from: data)
    #expect(decoded == original)
}

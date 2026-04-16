//
//  VPNMonitorTests.swift
//  ControllarrTests
//

import Testing
import Foundation
@testable import Services
@testable import Persistence

@Test func testVPNStatusSnapshot() {
    let status = VPNMonitor.Status(
        enabled: true,
        isConnected: true,
        interfaceName: "utun4",
        interfaceIP: "10.47.0.1",
        killSwitchEngaged: false,
        pausedHashes: [],
        boundToVPN: true
    )
    #expect(status.enabled == true)
    #expect(status.isConnected == true)
    #expect(status.interfaceName == "utun4")
    #expect(status.interfaceIP == "10.47.0.1")
    #expect(status.killSwitchEngaged == false)
    #expect(status.pausedHashes.isEmpty)
    #expect(status.boundToVPN == true)
}

@Test func testVPNStatusDisconnected() {
    let hashes: Set<String> = ["aaa111", "bbb222", "ccc333"]
    let status = VPNMonitor.Status(
        enabled: true,
        isConnected: false,
        interfaceName: nil,
        interfaceIP: nil,
        killSwitchEngaged: true,
        pausedHashes: hashes,
        boundToVPN: false
    )
    #expect(status.isConnected == false)
    #expect(status.interfaceName == nil)
    #expect(status.interfaceIP == nil)
    #expect(status.killSwitchEngaged == true)
    #expect(status.pausedHashes.count == 3)
    #expect(status.boundToVPN == false)
}

@Test func testVPNSettingsDefaults() {
    let home = URL(fileURLWithPath: "/tmp/controllarr-test-home")
    let s = Settings.defaults(homeDir: home)
    #expect(s.vpnEnabled == false)
    #expect(s.vpnKillSwitch == true)
    #expect(s.vpnBindInterface == true)
    #expect(s.vpnInterfacePrefix == "utun")
    #expect(s.vpnMonitorIntervalSeconds == 5)
}

@Test func testVPNSettingsForwardCompatibleDecoding() throws {
    // Simulate a v1.0 state file that has no VPN fields.
    let home = URL(fileURLWithPath: "/tmp/controllarr-test-home")
    let oldSettings = """
    {
        "listenPortRangeStart": 49152,
        "listenPortRangeEnd": 65000,
        "stallThresholdMinutes": 10,
        "defaultSavePath": "/tmp/downloads",
        "webUIHost": "127.0.0.1",
        "webUIPort": 8791,
        "webUIUsername": "admin",
        "webUIPassword": "test"
    }
    """
    let data = oldSettings.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(Settings.self, from: data)
    // VPN fields should fall back to defaults.
    #expect(decoded.vpnEnabled == false)
    #expect(decoded.vpnKillSwitch == true)
    #expect(decoded.vpnBindInterface == true)
    #expect(decoded.vpnInterfacePrefix == "utun")
    #expect(decoded.vpnMonitorIntervalSeconds == 5)
}

@Test func testDetectVPNInterfaceNoMatch() {
    // Scanning for an impossible prefix should return nil.
    let result = VPNMonitor.detectVPNInterface(prefix: "zzz_nonexistent_interface_prefix_zzz")
    #expect(result == nil)
}

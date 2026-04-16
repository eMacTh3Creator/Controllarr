//
//  NetworkDiagnosticsTests.swift
//  ControllarrTests
//

import Testing
@testable import Services

@Test func testLoopbackBindIsNotRemoteConfigured() {
    let snapshot = NetworkDiagnostics.evaluate(
        bindHost: "127.0.0.1",
        bindPort: 8791,
        interfaces: [
            .init(name: "en0", ip: "192.168.1.122")
        ],
        vpnStatus: nil
    )

    #expect(snapshot.remoteAccessConfigured == false)
    #expect(snapshot.recommendedRemoteURL == nil)
    #expect(snapshot.warning?.contains("Remote LAN access is not configured") == true)
}

@Test func testWildcardBindUsesLoopbackLocallyAndSuggestsLANURL() {
    let snapshot = NetworkDiagnostics.evaluate(
        bindHost: "0.0.0.0",
        bindPort: 8791,
        interfaces: [
            .init(name: "en0", ip: "192.168.1.122")
        ],
        vpnStatus: nil
    )

    #expect(snapshot.remoteAccessConfigured == true)
    #expect(snapshot.localOpenURL == "http://127.0.0.1:8791/")
    #expect(snapshot.recommendedRemoteURL == "http://192.168.1.122:8791/")
}

@Test func testVPNWarningAppearsWhenLANConfigLooksCorrect() {
    let vpnStatus = VPNMonitor.Status(
        enabled: true,
        isConnected: true,
        interfaceName: "utun4",
        interfaceIP: "10.14.0.2",
        killSwitchEngaged: false,
        pausedHashes: [],
        boundToVPN: true
    )
    let snapshot = NetworkDiagnostics.evaluate(
        bindHost: "0.0.0.0",
        bindPort: 8791,
        interfaces: [
            .init(name: "en0", ip: "192.168.1.122")
        ],
        vpnStatus: vpnStatus
    )

    #expect(snapshot.remoteAccessConfigured == true)
    #expect(snapshot.vpnBoundToTorrentEngine == true)
    #expect(snapshot.warning?.contains("VPN client is probably blocking inbound LAN traffic") == true)
}

//
//  HealthMonitorTests.swift
//  ControllarrTests
//

import Testing
import Foundation
@testable import Services

@Test func testReasonRawValues() {
    #expect(HealthMonitor.Reason.metadataTimeout.rawValue == "metadata_timeout")
    #expect(HealthMonitor.Reason.noPeers.rawValue == "no_peers")
    #expect(HealthMonitor.Reason.stalledWithPeers.rawValue == "stalled_with_peers")
    #expect(HealthMonitor.Reason.awaitingRecheck.rawValue == "awaiting_recheck")
}

@Test func testReasonCodable() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let allCases: [HealthMonitor.Reason] = [
        .metadataTimeout,
        .noPeers,
        .stalledWithPeers,
        .awaitingRecheck,
    ]
    for reason in allCases {
        let data = try encoder.encode(reason)
        let decoded = try decoder.decode(HealthMonitor.Reason.self, from: data)
        #expect(decoded == reason)
    }
}

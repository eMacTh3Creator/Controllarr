//
//  ArrNotifierTests.swift
//  ControllarrTests
//

import Testing
import Foundation
@testable import Persistence

@Test func testArrEndpointKindRawValues() {
    #expect(ArrEndpoint.Kind.sonarr.rawValue == "sonarr")
    #expect(ArrEndpoint.Kind.radarr.rawValue == "radarr")
}

@Test func testArrEndpointCodable() throws {
    let original = ArrEndpoint(
        name: "my-sonarr",
        kind: .sonarr,
        baseURL: "http://localhost:8989",
        apiKeyInKeychain: true,
        apiKey: ""
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(ArrEndpoint.self, from: data)
    #expect(decoded == original)
    #expect(decoded.name == "my-sonarr")
    #expect(decoded.kind == .sonarr)
    #expect(decoded.baseURL == "http://localhost:8989")
    #expect(decoded.apiKeyInKeychain == true)
    #expect(decoded.apiKey.isEmpty)
}

@Test func testArrEndpointCodableRadarr() throws {
    let original = ArrEndpoint(
        name: "my-radarr",
        kind: .radarr,
        baseURL: "http://localhost:7878",
        apiKeyInKeychain: false,
        apiKey: "test-key-123"
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(ArrEndpoint.self, from: data)
    #expect(decoded == original)
    #expect(decoded.kind == .radarr)
}

@Test func testArrEndpointDefaults() {
    let home = URL(fileURLWithPath: "/tmp/controllarr-test-home")
    let s = Settings.defaults(homeDir: home)
    #expect(s.arrEndpoints.isEmpty)
    #expect(s.arrReSearchAfterHours == 6)
}

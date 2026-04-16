//
//  SeedingPolicyTests.swift
//  ControllarrTests
//

import Testing
import Foundation
@testable import Persistence

@Test func testSeedLimitActionRawValues() {
    #expect(SeedLimitAction.pause.rawValue == "pause")
    #expect(SeedLimitAction.removeKeepFiles.rawValue == "remove_keep_files")
    #expect(SeedLimitAction.removeDeleteFiles.rawValue == "remove_delete_files")
}

@Test func testSeedLimitActionCodable() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for action in SeedLimitAction.allCases {
        let data = try encoder.encode(action)
        let decoded = try decoder.decode(SeedLimitAction.self, from: data)
        #expect(decoded == action)
    }
}

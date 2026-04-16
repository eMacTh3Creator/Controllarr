//
//  KeychainTests.swift
//  ControllarrTests
//

import Testing
import Foundation
@testable import Persistence

/// Unique prefix to avoid collisions with real keychain data.
private let testPrefix = "com.controllarr.test.\(ProcessInfo.processInfo.globallyUniqueString)."

@Test func testSetAndGet() {
    let key = testPrefix + "setAndGet"
    defer { Keychain.delete(forKey: key) }

    Keychain.set("hello", forKey: key)
    let value = Keychain.get(forKey: key)
    #expect(value == "hello")
}

@Test func testOverwrite() {
    let key = testPrefix + "overwrite"
    defer { Keychain.delete(forKey: key) }

    Keychain.set("first", forKey: key)
    Keychain.set("second", forKey: key)
    let value = Keychain.get(forKey: key)
    #expect(value == "second")
}

@Test func testDelete() {
    let key = testPrefix + "delete"

    Keychain.set("temporary", forKey: key)
    Keychain.delete(forKey: key)
    let value = Keychain.get(forKey: key)
    #expect(value == nil)
}

@Test func testGetMissing() {
    let key = testPrefix + "neverSet"
    let value = Keychain.get(forKey: key)
    #expect(value == nil)
}

//
//  PostProcessorTests.swift
//  ControllarrTests
//

import Testing
import Foundation
@testable import Services

@Test func testFindArchivesEmpty() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("controllarr-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let result = PostProcessor.findArchives(under: tmp)
    #expect(result.isEmpty)
}

@Test func testFindArchivesRar() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("controllarr-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    // Create test files (zero-byte is fine — we're testing filename detection)
    FileManager.default.createFile(atPath: tmp.appendingPathComponent("movie.rar").path, contents: Data(), attributes: nil)
    FileManager.default.createFile(atPath: tmp.appendingPathComponent("subs.zip").path, contents: Data(), attributes: nil)
    FileManager.default.createFile(atPath: tmp.appendingPathComponent("readme.txt").path, contents: Data(), attributes: nil)

    let result = PostProcessor.findArchives(under: tmp)
    let names = result.map { $0.lastPathComponent }.sorted()
    #expect(names == ["movie.rar", "subs.zip"])
}

@Test func testFindArchivesMultipartRar() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("controllarr-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    FileManager.default.createFile(atPath: tmp.appendingPathComponent("movie.part1.rar").path, contents: Data(), attributes: nil)
    FileManager.default.createFile(atPath: tmp.appendingPathComponent("movie.part2.rar").path, contents: Data(), attributes: nil)
    FileManager.default.createFile(atPath: tmp.appendingPathComponent("movie.part3.rar").path, contents: Data(), attributes: nil)

    let result = PostProcessor.findArchives(under: tmp)
    #expect(result.count == 1)
    #expect(result[0].lastPathComponent == "movie.part1.rar")
}

@Test func testBsdtarMissing() {
    let fakeArchive = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).rar")
    let fakeDest = URL(fileURLWithPath: "/tmp")
    let result = PostProcessor.runBsdtar(archive: fakeArchive, destination: fakeDest)
    #expect(result.success == false)
}

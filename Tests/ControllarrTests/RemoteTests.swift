import Testing
import Foundation
@testable import HTTPServer
@testable import TorrentEngine
@testable import Persistence

private func fixture(_ hash: String, complete: Bool = false, error: String = "") -> TorrentStats {
    var result = TorrentStats(name: "Fixture", infoHash: hash, savePath: "/tmp/fixture", progress: complete ? 1 : 0.5,
        state: complete ? .seeding : .downloading, paused: false, downloadRate: 0, uploadRate: 0, totalWanted: 100,
        totalDone: complete ? 100 : 50, totalDownload: 50, totalUpload: 0, ratio: 0, numPeers: 0, numSeeds: 0,
        etaSeconds: -1, addedDate: Date(), category: nil)
    result.errorMessage = error
    return result
}

@Test func eventBaselineTransitionsAndRetention() async {
    let journal = RemoteEvents()
    await journal.observe([fixture("a", complete: true), fixture("b")], port: 53127, vpnEnabled: true, connected: true)
    let baseline = await journal.page(epoch: nil, cursor: nil)
    #expect(baseline.reset && baseline.events.isEmpty)
    await journal.observe([fixture("a", complete: true), fixture("b", complete: true, error: "Disk error")], port: 53128, vpnEnabled: true, connected: false)
    let page = await journal.page(epoch: baseline.epoch, cursor: baseline.cursor)
    #expect(Set(page.events.map(\.kind)) == ["completed", "error", "port_changed", "vpn_disconnected"])
    await journal.observe([fixture("a", complete: true), fixture("b", complete: true, error: "Disk error")], port: 53128, vpnEnabled: true, connected: false)
    #expect(await journal.page(epoch: page.epoch, cursor: page.cursor).events.isEmpty)
    for i in 1...600 { await journal.observe([], port: UInt16(54000 + i), vpnEnabled: false, connected: false) }
    #expect(await journal.page(epoch: baseline.epoch, cursor: baseline.cursor).reset)
    let tail = await journal.page(epoch: page.epoch, cursor: 604 - 512)
    #expect(tail.events.count <= 512)
}

@Test func sonarrContentPathIsDistinctFromReportedBase() {
    var torrent = fixture("test", complete: true)
    torrent.contentPath = "/tmp/fixture/file.mkv"
    torrent.apiSavePath = "/tmp"
    let info = QBTorrentInfo.from(torrent, categoryOverlay: [:]).asDictionary
    #expect(info["save_path"] as? String == "/tmp")
    #expect(info["content_path"] as? String == "/tmp/fixture/file.mkv")
    torrent.errorMessage = "Disk error"
    #expect(QBTorrentInfo.mapState(torrent) == "error")
    torrent.errorMessage = ""
    torrent.hasMetadata = false
    #expect(QBTorrentInfo.mapState(torrent) != "pausedUP")
}

@Test func thousandTorrentEngineSnapshotAndBulkRemoval() async throws {
    guard ProcessInfo.processInfo.environment["CONTROLLARR_ENGINE_LOAD"] == "1" else { return }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("controllarr-load-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let engine = TorrentEngine(defaultSavePath: root.appendingPathComponent("downloads"), resumeDataDirectory: root.appendingPathComponent("resume"), listenPort: 0, folderPolicy: { _ in true })
    let clock = ContinuousClock()
    let start = clock.now
    for i in 0..<1000 {
        let name = "fixture-\(i).bin"
        let payload = "d4:infod6:lengthi16384e4:name\(name.utf8.count):\(name)12:piece lengthi16384e6:pieces20:" + String(repeating: "x", count: 20) + "ee"
        let path = root.appendingPathComponent("input.torrent")
        try Data(payload.utf8).write(to: path)
        let hash = try await engine.addTorrentFile(at: path)
        #expect(!hash.isEmpty)
    }
    let rows = await engine.pollStats()
    #expect(rows.count == 1000)
    #expect(Set(rows.map(\.infoHash)).count == 1000)
    #expect(rows.allSatisfy { $0.hasMetadata && !$0.contentPath.isEmpty && $0.apiSavePath != $0.contentPath })
    await engine.saveResumeData()
    for _ in 0..<5 { await engine.drainAlerts() }
    #expect(await engine.remove(hashes: rows.map(\.infoHash), deleteFiles: false) == 1000)
    #expect(await engine.pollStats().isEmpty)
    await engine.shutdown()
    #expect(await engine.pollStats().isEmpty)
    print("BENCH: real libtorrent 1,000 paused local torrents, intake/snapshot/checkpoint/bulk removal/shutdown: \(start.duration(to: clock.now))")
}

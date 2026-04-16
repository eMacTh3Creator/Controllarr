//
//  TorrentEnginePerformanceTests.swift
//  ControllarrTests
//

import Testing
import Foundation
@testable import TorrentEngine

@Test func testSessionSummaryAggregatesTorrentSnapshotInSinglePass() {
    let torrents = [
        TorrentStats(
            name: "Ubuntu ISO",
            infoHash: "hash-1",
            savePath: "/tmp",
            progress: 1.0,
            state: .seeding,
            paused: false,
            downloadRate: 1_000,
            uploadRate: 500,
            totalWanted: 10_000,
            totalDone: 10_000,
            totalDownload: 12_000,
            totalUpload: 6_000,
            ratio: 0.5,
            numPeers: 12,
            numSeeds: 8,
            etaSeconds: -1,
            addedDate: Date(),
            category: "linux"
        ),
        TorrentStats(
            name: "Fedora ISO",
            infoHash: "hash-2",
            savePath: "/tmp",
            progress: 0.4,
            state: .downloading,
            paused: false,
            downloadRate: 2_500,
            uploadRate: 250,
            totalWanted: 20_000,
            totalDone: 8_000,
            totalDownload: 9_000,
            totalUpload: 1_000,
            ratio: 0.11,
            numPeers: 30,
            numSeeds: 14,
            etaSeconds: 120,
            addedDate: Date(),
            category: "linux"
        ),
    ]

    let summary = TorrentEngine.summarizeSession(torrents: torrents, listenPort: 8791)

    #expect(summary.downloadRate == 3_500)
    #expect(summary.uploadRate == 750)
    #expect(summary.totalDownloaded == 21_000)
    #expect(summary.totalUploaded == 7_000)
    #expect(summary.numTorrents == 2)
    #expect(summary.numPeersConnected == 42)
    #expect(summary.hasIncomingConnections == true)
    #expect(summary.listenPort == 8791)
}

@Test func testSessionSummaryHandlesIdleSnapshotWithoutPeers() {
    let summary = TorrentEngine.summarizeSession(
        torrents: [
            TorrentStats(
                name: "Idle Torrent",
                infoHash: "hash-idle",
                savePath: "/tmp",
                progress: 0.0,
                state: .paused,
                paused: true,
                downloadRate: 0,
                uploadRate: 0,
                totalWanted: 0,
                totalDone: 0,
                totalDownload: 0,
                totalUpload: 0,
                ratio: 0,
                numPeers: 0,
                numSeeds: 0,
                etaSeconds: -1,
                addedDate: Date(),
                category: nil
            ),
        ],
        listenPort: 0
    )

    #expect(summary.downloadRate == 0)
    #expect(summary.uploadRate == 0)
    #expect(summary.numPeersConnected == 0)
    #expect(summary.hasIncomingConnections == false)
}

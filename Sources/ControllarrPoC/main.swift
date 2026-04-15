//
//  ControllarrPoC/main.swift
//
//  Phase 0 proof of concept. Usage:
//
//      swift run ControllarrPoC "<magnet-or-path>"
//
//  The PoC spins up a libtorrent session, adds whatever the user handed in,
//  and prints a status line once a second until the torrent finishes or the
//  user hits Ctrl-C. If this runs end-to-end on Apple Silicon, the whole
//  Swift ↔ ObjC++ ↔ libtorrent wiring is proven and we can move on to
//  Phase 1.
//

import Foundation
import TorrentEngine

// MARK: - Args

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: ControllarrPoC <magnet-uri-or-torrent-file>\n".utf8))
    exit(2)
}
let target = args[1]

// MARK: - Save path

let saveDir = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("Controllarr-PoC", isDirectory: true)
try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)

print("[Controllarr PoC] save path: \(saveDir.path)")

// MARK: - Bring up engine

let engine = TorrentEngine(savePath: saveDir, listenPort: 6881)

do {
    if target.hasPrefix("magnet:") {
        print("[Controllarr PoC] adding magnet…")
        try engine.addMagnet(target)
    } else {
        print("[Controllarr PoC] adding torrent file: \(target)")
        try engine.addTorrentFile(at: URL(fileURLWithPath: target))
    }
} catch {
    FileHandle.standardError.write(Data("add failed: \(error)\n".utf8))
    exit(1)
}

// MARK: - Poll loop

func fmtRate(_ bps: Int64) -> String {
    let kb = Double(bps) / 1024.0
    if kb < 1024 { return String(format: "%6.1f KiB/s", kb) }
    return String(format: "%6.2f MiB/s", kb / 1024.0)
}

func fmtSize(_ b: Int64) -> String {
    let mb = Double(b) / 1_048_576.0
    if mb < 1024 { return String(format: "%7.1f MiB", mb) }
    return String(format: "%7.2f GiB", mb / 1024.0)
}

print("[Controllarr PoC] polling — Ctrl-C to stop")
print(String(repeating: "-", count: 78))

var tick = 0
while true {
    engine.drainAlerts()
    let stats = engine.pollStats()
    if stats.isEmpty {
        print("waiting for metadata…")
    } else {
        for s in stats {
            let pct = String(format: "%5.1f%%", s.progress * 100)
            let name = s.name.isEmpty ? "(no name yet)" : s.name
            let short = name.count > 40 ? String(name.prefix(37)) + "..." : name
            print("\(short.padding(toLength: 40, withPad: " ", startingAt: 0))  \(pct)  d:\(fmtRate(s.downloadRate))  u:\(fmtRate(s.uploadRate))  peers:\(s.numPeers)/\(s.numPeers + s.numSeeds)  done:\(fmtSize(s.totalDone))/\(fmtSize(s.totalWanted))  state:\(s.state)")

            if s.state == .seeding || s.state == .finished {
                print("[Controllarr PoC] finished — shutting down")
                engine.shutdown()
                exit(0)
            }
        }
    }
    tick += 1
    Thread.sleep(forTimeInterval: 1.0)
}

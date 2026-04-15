//
//  ControllarrPoC/main.swift
//
//  Phase 0 smoke test — still useful as a one-shot libtorrent sanity
//  check. Usage:
//
//      swift run ControllarrPoC "<magnet-or-path>"
//

import Foundation
import TorrentEngine

setbuf(stdout, nil) // Phase 0 lesson: don't lose logs on kill.

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: ControllarrPoC <magnet-uri-or-torrent-file>\n".utf8))
    exit(2)
}
let target = args[1]

let saveDir = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("Controllarr-PoC", isDirectory: true)
let resumeDir = saveDir.appendingPathComponent("resume", isDirectory: true)
try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)

print("[Controllarr PoC] save path: \(saveDir.path)")

let engine = TorrentEngine(
    defaultSavePath: saveDir,
    resumeDataDirectory: resumeDir,
    listenPort: 6881
)

Task {
    do {
        if target.hasPrefix("magnet:") {
            print("[Controllarr PoC] adding magnet")
            _ = try await engine.addMagnet(target)
        } else {
            print("[Controllarr PoC] adding torrent file: \(target)")
            _ = try await engine.addTorrentFile(at: URL(fileURLWithPath: target))
        }
    } catch {
        FileHandle.standardError.write(Data("add failed: \(error)\n".utf8))
        exit(1)
    }
}

func fmtRate(_ bps: Int64) -> String {
    let kb = Double(bps) / 1024.0
    if kb < 1024 { return String(format: "%6.1f KiB/s", kb) }
    return String(format: "%6.2f MiB/s", kb / 1024.0)
}

print("[Controllarr PoC] polling — Ctrl-C to stop")
print(String(repeating: "-", count: 78))

while true {
    Task {
        await engine.drainAlerts()
        let stats = await engine.pollStats()
        if stats.isEmpty {
            print("waiting for metadata")
        } else {
            for s in stats {
                let pct = String(format: "%5.1f%%", s.progress * 100)
                let name = s.name.isEmpty ? "(no name yet)" : s.name
                let short = name.count > 40 ? String(name.prefix(37)) + "..." : name
                print("\(short.padding(toLength: 40, withPad: " ", startingAt: 0))  \(pct)  d:\(fmtRate(s.downloadRate))  u:\(fmtRate(s.uploadRate))  peers:\(s.numPeers)  state:\(s.state)")
                if s.state == .seeding || s.state == .finished {
                    print("[Controllarr PoC] finished")
                    await engine.shutdown()
                    exit(0)
                }
            }
        }
    }
    Thread.sleep(forTimeInterval: 1.0)
}

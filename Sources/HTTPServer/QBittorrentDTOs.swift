//
//  QBittorrentDTOs.swift
//  Controllarr — Phase 1
//
//  Shapes of the JSON objects Sonarr/Radarr expect back from the qBit
//  API. We build plain `[String: Any]` dictionaries instead of Codable
//  structs so we can match qBit's exact key names (snake_case and Hungarian
//  mixed together) without per-field CodingKeys noise.
//

import Foundation
import TorrentEngine
import Persistence

/// One row in /api/v2/torrents/info
struct QBTorrentInfo {
    let hash: String
    let name: String
    let size: Int64
    let progress: Double
    let dlspeed: Int64
    let upspeed: Int64
    let state: String
    let savePath: String
    let category: String
    let addedOn: Int64
    let completed: Int64
    let ratio: Double
    let numSeeds: Int
    let numLeechs: Int
    let eta: Int

    static func from(_ t: TorrentStats, categoryOverlay: [String: String]) -> QBTorrentInfo {
        QBTorrentInfo(
            hash: t.infoHash,
            name: t.name,
            size: t.totalWanted,
            progress: Double(t.progress),
            dlspeed: t.downloadRate,
            upspeed: t.uploadRate,
            state: mapState(t),
            savePath: t.savePath,
            category: t.category ?? categoryOverlay[t.infoHash] ?? "",
            addedOn: Int64(t.addedDate.timeIntervalSince1970),
            completed: t.totalDone,
            ratio: t.ratio,
            numSeeds: t.numSeeds,
            numLeechs: t.numPeers,
            eta: t.etaSeconds
        )
    }

    static func mapState(_ t: TorrentStats) -> String {
        // qBittorrent canonical states that Sonarr/Radarr actually look
        // for: pausedDL, pausedUP, downloading, metaDL, uploading/stalledUP,
        // queuedDL, queuedUP, checkingDL, checkingUP, error, missingFiles.
        if t.paused { return t.totalDone >= t.totalWanted ? "pausedUP" : "pausedDL" }
        switch t.state {
        case .downloading:          return t.downloadRate > 0 ? "downloading" : "stalledDL"
        case .downloadingMetadata:  return "metaDL"
        case .finished, .seeding:   return t.uploadRate > 0 ? "uploading" : "stalledUP"
        case .checkingFiles:        return "checkingDL"
        case .checkingResume:       return "checkingResumeData"
        case .paused:               return "pausedDL"
        case .unknown:              return "unknown"
        }
    }

    var asDictionary: [String: Any] {
        [
            "hash":          hash,
            "name":          name,
            "size":          size,
            "progress":      progress,
            "dlspeed":       dlspeed,
            "upspeed":       upspeed,
            "state":         state,
            "save_path":     savePath,
            "category":      category,
            "added_on":      addedOn,
            "completed":     completed,
            "ratio":         ratio,
            "num_seeds":     numSeeds,
            "num_leechs":    numLeechs,
            "eta":           eta,
            "priority":      0,
            "seq_dl":        false,
            "f_l_piece_prio":false,
            "force_start":   false,
            "super_seeding": false,
            "auto_tmm":      true,
            "tracker":       "",
            "tags":          "",
        ]
    }
}

struct QBTorrentProperties {
    let savePath: String
    let totalSize: Int64
    let totalDownloaded: Int64
    let totalUploaded: Int64
    let dlSpeed: Int64
    let upSpeed: Int64
    let pieces: Int
    let piecesHave: Int
    let eta: Int
    let ratio: Double
    let addedOn: Int64

    static func from(_ t: TorrentStats) -> QBTorrentProperties {
        QBTorrentProperties(
            savePath: t.savePath,
            totalSize: t.totalWanted,
            totalDownloaded: t.totalDownload,
            totalUploaded: t.totalUpload,
            dlSpeed: t.downloadRate,
            upSpeed: t.uploadRate,
            pieces: 0,
            piecesHave: 0,
            eta: t.etaSeconds,
            ratio: t.ratio,
            addedOn: Int64(t.addedDate.timeIntervalSince1970)
        )
    }

    var asDictionary: [String: Any] {
        [
            "save_path":         savePath,
            "total_size":        totalSize,
            "total_downloaded":  totalDownloaded,
            "total_uploaded":    totalUploaded,
            "dl_speed":          dlSpeed,
            "up_speed":          upSpeed,
            "pieces_num":        pieces,
            "pieces_have":       piecesHave,
            "eta":               eta,
            "share_ratio":       ratio,
            "addition_date":     addedOn,
        ]
    }
}

/// Minimal preferences object. Sonarr/Radarr mainly read `save_path`,
/// `listen_port`, `max_ratio_enabled`, and a few cosmetic fields.
struct Preferences {
    let savePath: String
    let listenPort: Int
    let webUIUsername: String
    let dhtEnabled: Bool

    static func from(settings: Settings, listenPort: Int) -> Preferences {
        Preferences(
            savePath: settings.defaultSavePath,
            listenPort: listenPort,
            webUIUsername: settings.webUIUsername,
            dhtEnabled: true
        )
    }

    var asDictionary: [String: Any] {
        [
            "save_path":              savePath,
            "temp_path":              savePath,
            "temp_path_enabled":      false,
            "listen_port":            listenPort,
            "random_port":            false,
            "upnp":                   true,
            "dht":                    dhtEnabled,
            "pex":                    true,
            "lsd":                    false,
            "encryption":             1,
            "max_ratio_enabled":      false,
            "max_ratio":              -1.0,
            "max_seeding_time_enabled": false,
            "max_seeding_time":       -1,
            "queueing_enabled":       true,
            "max_active_downloads":   5,
            "max_active_torrents":    10,
            "max_active_uploads":     5,
            "web_ui_username":        webUIUsername,
            "preallocate_all":        false,
            "incomplete_files_ext":   false,
            "auto_tmm_enabled":       true,
            "torrent_content_layout": "Original",
            "locale":                 "en",
        ]
    }
}

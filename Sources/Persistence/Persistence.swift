//
//  Persistence.swift
//  Controllarr
//
//  Single-file JSON state store. SQLite will replace this later if we need
//  indexed queries for hit-and-run tracking at scale; for now a flat
//  document is enough and avoids a dependency.
//
//  State is kept in memory and flushed to disk on every mutation via a
//  cheap debounced write.
//

import Foundation

// MARK: - Value types

/// Policy applied when a torrent hits a seeding limit.
public enum SeedLimitAction: String, Codable, Sendable, CaseIterable {
    /// Pause the torrent in place. Files stay. Default.
    case pause
    /// Remove the torrent from the session but keep the files.
    case removeKeepFiles = "remove_keep_files"
    /// Remove the torrent and delete the downloaded files.
    case removeDeleteFiles = "remove_delete_files"
}

public struct Category: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    /// Where the torrent is downloaded initially. This is the path that
    /// goes into libtorrent's save_path at add-time.
    public var savePath: String
    /// Optional destination to move the torrent's storage to once it
    /// finishes. Typical usage: download to a fast scratch SSD
    /// (`savePath`), then move to the Plex library volume
    /// (`completePath`) for seeding.
    public var completePath: String?
    /// When true, Controllarr will scan finished torrents for .rar/.zip
    /// archives and extract them alongside the moved files.
    public var extractArchives: Bool
    /// Filename extensions Controllarr should not download for torrents
    /// in this category. Matched case-insensitively against the filename
    /// suffix. Enforced via libtorrent file priorities at add-time, so
    /// blocked files never touch disk.
    public var blockedExtensions: [String]
    /// Per-category override for the global max ratio. nil = inherit.
    public var maxRatio: Double?
    /// Per-category override for the global max seeding time (minutes).
    /// nil = inherit.
    public var maxSeedingTimeMinutes: Int?
    /// Glob-ish dangerous-file patterns — kept for backward compatibility
    /// with the Phase 1 schema. New code should use `blockedExtensions`.
    public var dangerousPatterns: [String]

    public init(
        name: String,
        savePath: String,
        completePath: String? = nil,
        extractArchives: Bool = false,
        blockedExtensions: [String] = [],
        maxRatio: Double? = nil,
        maxSeedingTimeMinutes: Int? = nil,
        dangerousPatterns: [String] = []
    ) {
        self.name = name
        self.savePath = savePath
        self.completePath = completePath
        self.extractArchives = extractArchives
        self.blockedExtensions = blockedExtensions
        self.maxRatio = maxRatio
        self.maxSeedingTimeMinutes = maxSeedingTimeMinutes
        self.dangerousPatterns = dangerousPatterns
    }

    // Custom decoder so v0.1.0 state files (which only have name/savePath/
    // dangerousPatterns) roll forward without losing data.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.savePath = try c.decode(String.self, forKey: .savePath)
        self.completePath = try c.decodeIfPresent(String.self, forKey: .completePath)
        self.extractArchives = try c.decodeIfPresent(Bool.self, forKey: .extractArchives) ?? false
        self.blockedExtensions = try c.decodeIfPresent([String].self, forKey: .blockedExtensions) ?? []
        self.maxRatio = try c.decodeIfPresent(Double.self, forKey: .maxRatio)
        self.maxSeedingTimeMinutes = try c.decodeIfPresent(Int.self, forKey: .maxSeedingTimeMinutes)
        self.dangerousPatterns = try c.decodeIfPresent([String].self, forKey: .dangerousPatterns) ?? []
    }
}

public struct BandwidthRule: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    /// Human-readable label for this rule (e.g. "Weekday daytime").
    public var name: String
    public var enabled: Bool
    /// Days of week this rule applies. 1=Sun, 2=Mon, …, 7=Sat.
    public var daysOfWeek: [Int]
    public var startHour: Int
    public var startMinute: Int
    public var endHour: Int
    public var endMinute: Int
    /// Max download speed in KiB/s. nil or 0 = unlimited.
    public var maxDownloadKBps: Int?
    /// Max upload speed in KiB/s. nil or 0 = unlimited.
    public var maxUploadKBps: Int?

    public init(
        name: String,
        enabled: Bool = true,
        daysOfWeek: [Int] = [2, 3, 4, 5, 6],
        startHour: Int = 8,
        startMinute: Int = 0,
        endHour: Int = 17,
        endMinute: Int = 0,
        maxDownloadKBps: Int? = nil,
        maxUploadKBps: Int? = nil
    ) {
        self.name = name
        self.enabled = enabled
        self.daysOfWeek = daysOfWeek
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.maxDownloadKBps = maxDownloadKBps
        self.maxUploadKBps = maxUploadKBps
    }
}

public struct Settings: Codable, Sendable, Equatable {
    /// Inclusive range of ports the PortWatcher may pick from when
    /// reselecting. Inclusive on both ends.
    public var listenPortRangeStart: UInt16
    public var listenPortRangeEnd: UInt16
    /// Minutes of zero-payload-transfer before PortWatcher considers the
    /// port stalled and cycles to a new one.
    public var stallThresholdMinutes: Int
    public var defaultSavePath: String
    public var webUIHost: String
    public var webUIPort: Int
    public var webUIUsername: String
    public var webUIPassword: String

    // Seeding policy ---------------------------------------------------------

    /// Global max share ratio. nil / ≤0 means unlimited. When a torrent
    /// exceeds this (and no category override says otherwise),
    /// `seedLimitAction` is applied.
    public var globalMaxRatio: Double?
    /// Global max seeding time in minutes. nil means unlimited.
    public var globalMaxSeedingTimeMinutes: Int?
    /// What to do when a seeding limit is reached.
    public var seedLimitAction: SeedLimitAction
    /// Minimum time (minutes) a torrent must seed before SeedingPolicy
    /// will remove/pause it, regardless of ratio. Protects against
    /// trackers that enforce a seed time for hit-and-run accounting.
    /// Applies to ALL torrents unless overridden per category.
    public var minimumSeedTimeMinutes: Int

    // Health monitor ---------------------------------------------------------

    /// Minutes of zero progress (with known metadata) before the health
    /// monitor flags a torrent as stalled.
    public var healthStallMinutes: Int
    /// Force an immediate reannounce when a torrent first stalls, in the
    /// hope of picking up new peers.
    public var healthReannounceOnStall: Bool

    // Bandwidth scheduler -------------------------------------------------------

    /// Time-of-day bandwidth limit windows. First matching window wins.
    public var bandwidthSchedule: [BandwidthRule]

    public static func defaults(homeDir: URL) -> Settings {
        Settings(
            listenPortRangeStart: 49152,
            listenPortRangeEnd:   65000,
            stallThresholdMinutes: 10,
            defaultSavePath: homeDir
                .appendingPathComponent("Downloads")
                .appendingPathComponent("Controllarr").path,
            webUIHost: "127.0.0.1",
            webUIPort: 8791,
            webUIUsername: "admin",
            webUIPassword: "adminadmin",
            globalMaxRatio: nil,
            globalMaxSeedingTimeMinutes: nil,
            seedLimitAction: .pause,
            minimumSeedTimeMinutes: 60,
            healthStallMinutes: 30,
            healthReannounceOnStall: true,
            bandwidthSchedule: []
        )
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.listenPortRangeStart = try c.decode(UInt16.self, forKey: .listenPortRangeStart)
        self.listenPortRangeEnd = try c.decode(UInt16.self, forKey: .listenPortRangeEnd)
        self.stallThresholdMinutes = try c.decode(Int.self, forKey: .stallThresholdMinutes)
        self.defaultSavePath = try c.decode(String.self, forKey: .defaultSavePath)
        self.webUIHost = try c.decode(String.self, forKey: .webUIHost)
        self.webUIPort = try c.decode(Int.self, forKey: .webUIPort)
        self.webUIUsername = try c.decode(String.self, forKey: .webUIUsername)
        self.webUIPassword = try c.decode(String.self, forKey: .webUIPassword)
        self.globalMaxRatio = try c.decodeIfPresent(Double.self, forKey: .globalMaxRatio)
        self.globalMaxSeedingTimeMinutes = try c.decodeIfPresent(Int.self, forKey: .globalMaxSeedingTimeMinutes)
        self.seedLimitAction = try c.decodeIfPresent(SeedLimitAction.self, forKey: .seedLimitAction) ?? .pause
        self.minimumSeedTimeMinutes = try c.decodeIfPresent(Int.self, forKey: .minimumSeedTimeMinutes) ?? 60
        self.healthStallMinutes = try c.decodeIfPresent(Int.self, forKey: .healthStallMinutes) ?? 30
        self.healthReannounceOnStall = try c.decodeIfPresent(Bool.self, forKey: .healthReannounceOnStall) ?? true
        self.bandwidthSchedule = try c.decodeIfPresent([BandwidthRule].self, forKey: .bandwidthSchedule) ?? []
    }

    public init(
        listenPortRangeStart: UInt16,
        listenPortRangeEnd: UInt16,
        stallThresholdMinutes: Int,
        defaultSavePath: String,
        webUIHost: String,
        webUIPort: Int,
        webUIUsername: String,
        webUIPassword: String,
        globalMaxRatio: Double?,
        globalMaxSeedingTimeMinutes: Int?,
        seedLimitAction: SeedLimitAction,
        minimumSeedTimeMinutes: Int,
        healthStallMinutes: Int,
        healthReannounceOnStall: Bool,
        bandwidthSchedule: [BandwidthRule] = []
    ) {
        self.listenPortRangeStart = listenPortRangeStart
        self.listenPortRangeEnd = listenPortRangeEnd
        self.stallThresholdMinutes = stallThresholdMinutes
        self.defaultSavePath = defaultSavePath
        self.webUIHost = webUIHost
        self.webUIPort = webUIPort
        self.webUIUsername = webUIUsername
        self.webUIPassword = webUIPassword
        self.globalMaxRatio = globalMaxRatio
        self.globalMaxSeedingTimeMinutes = globalMaxSeedingTimeMinutes
        self.seedLimitAction = seedLimitAction
        self.minimumSeedTimeMinutes = minimumSeedTimeMinutes
        self.healthStallMinutes = healthStallMinutes
        self.healthReannounceOnStall = healthReannounceOnStall
        self.bandwidthSchedule = bandwidthSchedule
    }
}

/// Full on-disk document.
public struct PersistedState: Codable, Sendable, Equatable {
    public var settings: Settings
    public var categories: [Category]
    /// infoHash -> category name. Denormalized overlay for torrents whose
    /// category was set at add-time.
    public var categoryByHash: [String: String]
    /// Listen port the app was using the last time it shut down cleanly.
    /// PortWatcher restores this on startup so we don't needlessly cycle.
    public var lastKnownGoodPort: UInt16?

    public init(
        settings: Settings,
        categories: [Category] = [],
        categoryByHash: [String: String] = [:],
        lastKnownGoodPort: UInt16? = nil
    ) {
        self.settings = settings
        self.categories = categories
        self.categoryByHash = categoryByHash
        self.lastKnownGoodPort = lastKnownGoodPort
    }
}

// MARK: - Store

public actor PersistenceStore {

    public static func defaultDirectory() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("Controllarr", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public nonisolated let directory: URL
    public nonisolated let stateFile: URL
    public nonisolated let resumeDir: URL
    private var state: PersistedState
    private var writeTask: Task<Void, Never>?

    public init(directory: URL = PersistenceStore.defaultDirectory()) {
        self.directory = directory
        self.stateFile = directory.appendingPathComponent("state.json")
        self.resumeDir = directory.appendingPathComponent("resume", isDirectory: true)

        let homeDir = URL(fileURLWithPath: NSHomeDirectory())
        let defaults = PersistedState(settings: Settings.defaults(homeDir: homeDir))

        if let data = try? Data(contentsOf: self.stateFile),
           let loaded = try? JSONDecoder().decode(PersistedState.self, from: data) {
            self.state = loaded
        } else {
            self.state = defaults
        }

        try? FileManager.default.createDirectory(at: resumeDir, withIntermediateDirectories: true)
    }

    // MARK: Read

    public func snapshot() -> PersistedState { state }
    public func settings() -> Settings { state.settings }
    public func categories() -> [Category] { state.categories }
    public func category(named name: String) -> Category? {
        state.categories.first { $0.name == name }
    }
    public func savePath(forCategory name: String) -> String? {
        category(named: name)?.savePath
    }

    // MARK: Write

    public func updateSettings(_ transform: (inout Settings) -> Void) {
        transform(&state.settings)
        scheduleFlush()
    }

    public func replaceSettings(_ newSettings: Settings) {
        state.settings = newSettings
        scheduleFlush()
    }

    public func upsertCategory(_ category: Category) {
        if let idx = state.categories.firstIndex(where: { $0.name == category.name }) {
            state.categories[idx] = category
        } else {
            state.categories.append(category)
        }
        scheduleFlush()
    }

    public func removeCategory(named name: String) {
        state.categories.removeAll { $0.name == name }
        scheduleFlush()
    }

    public func setCategoryMap(_ map: [String: String]) {
        state.categoryByHash = map
        scheduleFlush()
    }

    public func noteCategoryForHash(_ hash: String, category: String?) {
        if let category { state.categoryByHash[hash] = category }
        else { state.categoryByHash.removeValue(forKey: hash) }
        scheduleFlush()
    }

    public func setLastKnownGoodPort(_ port: UInt16?) {
        state.lastKnownGoodPort = port
        scheduleFlush()
    }

    // MARK: Flush

    private func scheduleFlush() {
        writeTask?.cancel()
        let snapshot = state
        let target = stateFile
        writeTask = Task.detached(priority: .utility) {
            // 250ms debounce — if another mutation lands, we overwrite.
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                let tmp = target.appendingPathExtension("tmp")
                try data.write(to: tmp, options: .atomic)
                _ = try? FileManager.default.replaceItemAt(target, withItemAt: tmp)
            } catch {
                NSLog("[Controllarr] persistence flush failed: \(error)")
            }
        }
    }

    public func flushNow() async {
        writeTask?.cancel()
        let snapshot = state
        let target = stateFile
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: target, options: .atomic)
        } catch {
            NSLog("[Controllarr] persistence flushNow failed: \(error)")
        }
    }
}

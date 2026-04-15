//
//  Persistence.swift
//  Controllarr — Phase 1
//
//  Single-file JSON state store. SQLite will replace this in Phase 5 once
//  we need indexed queries for HnR tracking; for now a flat document is
//  enough and avoids a dependency.
//
//  State is kept in memory and flushed to disk on every mutation via a
//  cheap debounced write.
//

import Foundation

// MARK: - Value types

public struct Category: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var savePath: String
    /// Glob-ish patterns that Controllarr should refuse to write to disk
    /// for this category. Matched against filename only. Phase 1 stores
    /// these but does not yet enforce them (enforcement lands in Phase 3).
    public var dangerousPatterns: [String]

    public init(name: String, savePath: String, dangerousPatterns: [String] = []) {
        self.name = name
        self.savePath = savePath
        self.dangerousPatterns = dangerousPatterns
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
    /// Plain-text password for the embedded WebUI. Stored plain because
    /// Controllarr is bound to localhost by default; if you open it up to
    /// the LAN, use a long string.
    public var webUIUsername: String
    public var webUIPassword: String

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
            webUIPassword: "adminadmin"
        )
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


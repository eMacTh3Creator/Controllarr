//
//  Logger.swift
//  Controllarr
//
//  Ring-buffer log sink shared by every runtime service. Appends are
//  cheap, fan-out to NSLog for developer visibility, and the buffer
//  itself is exposed so the SwiftUI and Web UIs can render a live log
//  viewer without any extra persistence.
//

import Foundation

public actor Logger {

    public enum Level: String, Sendable, Codable, Comparable {
        case debug, info, warn, error

        public var sortOrder: Int {
            switch self {
            case .debug: return 0
            case .info:  return 1
            case .warn:  return 2
            case .error: return 3
            }
        }

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.sortOrder < rhs.sortOrder
        }
    }

    public struct Entry: Sendable, Codable, Identifiable {
        public let id: UUID
        public let timestamp: Date
        public let level: Level
        public let source: String
        public let message: String

        public init(level: Level, source: String, message: String) {
            self.id = UUID()
            self.timestamp = Date()
            self.level = level
            self.source = source
            self.message = message
        }
    }

    private let capacity: Int
    private var buffer: [Entry] = []

    // Persistent log file. The in-memory ring buffer is lost when the app (or
    // the whole machine) goes down, which is exactly when we most want the
    // record. Mirroring entries to disk — and fsync'ing frequently — keeps a
    // post-mortem trail that survives crashes and reboots.
    private let fileURL: URL?
    private var fileHandle: FileHandle?
    private var bytesWritten: Int = 0
    private var linesSinceSync: Int = 0
    private let maxFileBytes = 5 * 1024 * 1024   // rotate at ~5 MB, keep one old file
    private let lineFormatter: ISO8601DateFormatter

    public init(capacity: Int = 500, fileURL: URL? = nil) {
        self.capacity = capacity
        self.fileURL = fileURL
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.lineFormatter = df
    }

    /// Absolute path of the on-disk log, if persistence is enabled. Exposed so
    /// the UI can offer a "Reveal in Finder" affordance.
    nonisolated public var logFilePath: String? { fileURL?.path }

    nonisolated public func debug(_ source: String, _ message: String) {
        append(level: .debug, source: source, message: message)
    }
    nonisolated public func info(_ source: String, _ message: String) {
        append(level: .info, source: source, message: message)
    }
    nonisolated public func warn(_ source: String, _ message: String) {
        append(level: .warn, source: source, message: message)
    }
    nonisolated public func error(_ source: String, _ message: String) {
        append(level: .error, source: source, message: message)
    }

    nonisolated private func append(level: Level, source: String, message: String) {
        let entry = Entry(level: level, source: source, message: message)
        NSLog("[\(level.rawValue.uppercased())] [\(source)] \(message)")
        Task { await self.store(entry) }
    }

    private func store(_ entry: Entry) {
        buffer.append(entry)
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
        writeToFile(entry)
    }

    // MARK: - Persistent file

    private func openFileIfNeeded() {
        guard fileHandle == nil, let fileURL else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: fileURL)
        if let h = fileHandle {
            bytesWritten = Int((try? h.seekToEnd()) ?? 0)
        }
    }

    private func writeToFile(_ entry: Entry) {
        guard fileURL != nil else { return }
        openFileIfNeeded()
        guard let h = fileHandle else { return }
        let line = "\(lineFormatter.string(from: entry.timestamp)) [\(entry.level.rawValue.uppercased())] [\(entry.source)] \(entry.message)\n"
        guard let data = line.data(using: .utf8) else { return }
        do {
            try h.write(contentsOf: data)
            bytesWritten += data.count
            linesSinceSync += 1
            // Flush to disk on every warning/error and otherwise every few
            // lines, so a kernel panic / power loss drops as little as possible.
            if entry.level >= .warn || linesSinceSync >= 5 {
                try? h.synchronize()
                linesSinceSync = 0
            }
            if bytesWritten >= maxFileBytes {
                rotate()
            }
        } catch {
            try? h.close()
            fileHandle = nil
        }
    }

    private func rotate() {
        guard let fileURL else { return }
        try? fileHandle?.synchronize()
        try? fileHandle?.close()
        fileHandle = nil
        let backup = URL(fileURLWithPath: fileURL.path + ".1")
        let fm = FileManager.default
        try? fm.removeItem(at: backup)
        try? fm.moveItem(at: fileURL, to: backup)
        bytesWritten = 0
        openFileIfNeeded()
    }

    public func snapshot(limit: Int = 500) -> [Entry] {
        let slice = buffer.suffix(limit)
        return Array(slice)
    }

    public func clear() {
        buffer.removeAll()
    }
}

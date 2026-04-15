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

    public init(capacity: Int = 500) {
        self.capacity = capacity
    }

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
    }

    public func snapshot(limit: Int = 500) -> [Entry] {
        let slice = buffer.suffix(limit)
        return Array(slice)
    }

    public func clear() {
        buffer.removeAll()
    }
}

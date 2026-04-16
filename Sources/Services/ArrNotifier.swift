//
//  ArrNotifier.swift
//  Controllarr
//
//  Watches the HealthMonitor for torrents that have been stalled beyond
//  `arrReSearchAfterHours` and triggers a re-search via the Sonarr or
//  Radarr API. This lets Controllarr proactively request fresh results
//  when a torrent's swarm is dead, rather than waiting for a user to
//  notice and manually search again.
//
//  Each stalled torrent is only notified once. The set resets if the
//  torrent recovers or is removed.
//

import Foundation
import TorrentEngine
import Persistence

public actor ArrNotifier {

    public struct Notification: Sendable, Identifiable, Codable {
        public var id: String { "\(infoHash)-\(timestamp.timeIntervalSince1970)" }
        public let infoHash: String
        public let name: String
        public let endpoint: String
        public let success: Bool
        public let message: String
        public let timestamp: Date
    }

    private let engine: TorrentEngine
    private let store: PersistenceStore
    private let healthMonitor: HealthMonitor
    private let logger: Logger

    /// Torrents we've already notified about. Reset when the torrent
    /// is removed from the health monitor (recovered or deleted).
    private var notified: Set<String> = []
    private var log: [Notification] = []
    private static let maxLogEntries = 200

    public init(engine: TorrentEngine, store: PersistenceStore,
                healthMonitor: HealthMonitor, logger: Logger) {
        self.engine = engine
        self.store = store
        self.healthMonitor = healthMonitor
        self.logger = logger
    }

    public func snapshot() -> [Notification] { log }

    /// Called from the tick loop. Checks health issues and fires
    /// re-search requests for stalled torrents that exceed the threshold.
    public func tick() async {
        let settings = await store.settings()
        let endpoints = settings.arrEndpoints
        guard !endpoints.isEmpty else { return }

        let thresholdSeconds = Double(max(1, settings.arrReSearchAfterHours)) * 3600

        let issues = await healthMonitor.snapshot()
        let now = Date()

        // Clean up notified set — remove hashes that are no longer in issues.
        let issueHashes = Set(issues.map(\.infoHash))
        notified = notified.intersection(issueHashes)

        for issue in issues {
            guard !notified.contains(issue.infoHash) else { continue }
            guard now.timeIntervalSince(issue.firstSeen) >= thresholdSeconds else { continue }

            // Determine which endpoint to use. Look up the torrent's category
            // to guess whether it's a movie (radarr) or show (sonarr).
            // If no category match, notify all endpoints.
            let torrentCategory = await categoryForHash(issue.infoHash)
            let matchedEndpoints = matchEndpoints(endpoints, category: torrentCategory)

            for ep in matchedEndpoints {
                let apiKey = await store.arrAPIKey(forEndpoint: ep.name)
                guard !apiKey.isEmpty else {
                    logger.warn("arr", "no API key for endpoint \(ep.name) — skipping re-search for \(issue.name)")
                    continue
                }
                let result = await sendReSearch(endpoint: ep, apiKey: apiKey, torrentName: issue.name)
                let entry = Notification(
                    infoHash: issue.infoHash,
                    name: issue.name,
                    endpoint: ep.name,
                    success: result.success,
                    message: result.message,
                    timestamp: now
                )
                log.append(entry)
                if log.count > Self.maxLogEntries { log.removeFirst() }

                if result.success {
                    logger.info("arr", "re-search triggered via \(ep.name) for \(issue.name)")
                } else {
                    logger.warn("arr", "re-search failed via \(ep.name) for \(issue.name): \(result.message)")
                }
            }

            notified.insert(issue.infoHash)
        }
    }

    // MARK: - Internals

    private func categoryForHash(_ hash: String) async -> String? {
        let torrents = await engine.pollStats()
        return torrents.first(where: { $0.infoHash == hash })?.category
    }

    /// Simple heuristic: if the category name contains "movie" or "radarr",
    /// prefer radarr endpoints. If it contains "tv", "series", or "sonarr",
    /// prefer sonarr. Otherwise, notify all configured endpoints.
    private func matchEndpoints(_ endpoints: [ArrEndpoint], category: String?) -> [ArrEndpoint] {
        guard let cat = category?.lowercased(), !cat.isEmpty else {
            return endpoints
        }
        let isMovie = cat.contains("movie") || cat.contains("radarr") || cat.contains("film")
        let isTV = cat.contains("tv") || cat.contains("series") || cat.contains("sonarr") || cat.contains("show")

        if isMovie {
            let filtered = endpoints.filter { $0.kind == .radarr }
            return filtered.isEmpty ? endpoints : filtered
        }
        if isTV {
            let filtered = endpoints.filter { $0.kind == .sonarr }
            return filtered.isEmpty ? endpoints : filtered
        }
        return endpoints
    }

    private struct SearchResult {
        let success: Bool
        let message: String
    }

    private func sendReSearch(endpoint: ArrEndpoint, apiKey: String, torrentName: String) async -> SearchResult {
        let commandName: String
        switch endpoint.kind {
        case .sonarr: commandName = "MissingEpisodeSearch"
        case .radarr: commandName = "MoviesSearch"
        }

        let urlString = endpoint.baseURL.hasSuffix("/")
            ? "\(endpoint.baseURL)api/v3/command"
            : "\(endpoint.baseURL)/api/v3/command"

        guard let url = URL(string: urlString) else {
            return SearchResult(success: false, message: "invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-Api-Key")

        let payload: [String: Any] = ["name": commandName]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return SearchResult(success: false, message: "failed to serialize request body")
        }
        request.httpBody = body
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if (200..<300).contains(http.statusCode) {
                    return SearchResult(success: true, message: "HTTP \(http.statusCode)")
                }
                let bodyStr = String(data: data.prefix(500), encoding: .utf8) ?? ""
                return SearchResult(success: false, message: "HTTP \(http.statusCode): \(bodyStr)")
            }
            return SearchResult(success: false, message: "unexpected response type")
        } catch {
            return SearchResult(success: false, message: error.localizedDescription)
        }
    }
}

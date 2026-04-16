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

/// Issue classes the recovery engine can match against.
public enum RecoveryTrigger: String, Codable, Sendable, CaseIterable {
    // Health-based (from HealthMonitor)
    case metadataTimeout = "metadata_timeout"
    case noPeers = "no_peers"
    case stalledWithPeers = "stalled_with_peers"
    case awaitingRecheck = "awaiting_recheck"
    // Post-processing failures (from PostProcessor)
    case postProcessMoveFailed = "post_process_move_failed"
    case postProcessExtractionFailed = "post_process_extraction_failed"
    // Disk pressure (from DiskSpaceMonitor)
    case diskPressure = "disk_pressure"
}

/// What to do when a torrent's category changes to one with a different save
/// path, or when a category's save path is edited while it has members.
public enum CategoryMovePolicy: String, Codable, Sendable, CaseIterable {
    /// Ask the user (native UI). WebUI treats this as "never" unless the
    /// request explicitly opts in via `moveFiles=true`.
    case ask
    /// Always move files when paths differ. No prompt.
    case always
    /// Never move files automatically. Operator must trigger move manually.
    case never
}

/// Action Controllarr should take when a recovery rule triggers.
public enum RecoveryAction: String, Codable, Sendable, CaseIterable {
    case reannounce
    case pause
    case removeKeepFiles = "remove_keep_files"
    case removeDeleteFiles = "remove_delete_files"
    case retryPostProcess = "retry_post_process"
}

public struct RecoveryRule: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(trigger.rawValue)-\(action.rawValue)-\(delayMinutes)" }
    public var enabled: Bool
    public var trigger: RecoveryTrigger
    public var action: RecoveryAction
    public var delayMinutes: Int

    public init(
        enabled: Bool = false,
        trigger: RecoveryTrigger,
        action: RecoveryAction,
        delayMinutes: Int
    ) {
        self.enabled = enabled
        self.trigger = trigger
        self.action = action
        self.delayMinutes = delayMinutes
    }
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

/// Network-discovery toggles passed straight through to libtorrent.
public struct PeerDiscovery: Codable, Sendable, Equatable {
    /// Distributed Hash Table — trackerless peer discovery over Kademlia.
    public var dhtEnabled: Bool
    /// Peer Exchange — learn new peers from already-connected peers.
    public var pexEnabled: Bool
    /// Local Service Discovery — mDNS-style peer find on the LAN.
    public var lsdEnabled: Bool

    public init(dhtEnabled: Bool = true, pexEnabled: Bool = true, lsdEnabled: Bool = false) {
        self.dhtEnabled = dhtEnabled
        self.pexEnabled = pexEnabled
        self.lsdEnabled = lsdEnabled
    }
}

/// libtorrent connection-count ceilings. nil/0 = inherit libtorrent defaults.
public struct ConnectionLimits: Codable, Sendable, Equatable {
    /// Max peer connections session-wide.
    public var globalMaxConnections: Int?
    /// Max peer connections per torrent.
    public var maxConnectionsPerTorrent: Int?
    /// Max simultaneous outgoing "unchoked" uploads session-wide.
    public var globalMaxUploads: Int?
    /// Max unchoked uploads per torrent.
    public var maxUploadsPerTorrent: Int?

    public init(
        globalMaxConnections: Int? = nil,
        maxConnectionsPerTorrent: Int? = nil,
        globalMaxUploads: Int? = nil,
        maxUploadsPerTorrent: Int? = nil
    ) {
        self.globalMaxConnections = globalMaxConnections
        self.maxConnectionsPerTorrent = maxConnectionsPerTorrent
        self.globalMaxUploads = globalMaxUploads
        self.maxUploadsPerTorrent = maxUploadsPerTorrent
    }
}

/// WebUI remote-access allowlist. CIDR notation supported (e.g. "10.0.0.0/8",
/// "192.168.1.0/24"). Bare IPs also accepted. Empty = allow all.
public struct WebUISecurity: Codable, Sendable, Equatable {
    /// When true, the IP allowlist is enforced. When false, WebUI is open to
    /// any caller that reaches the bind address.
    public var allowlistEnabled: Bool
    public var allowedCIDRs: [String]
    /// When true, adds `X-Frame-Options: DENY` and a restrictive
    /// Content-Security-Policy so the WebUI cannot be framed.
    public var clickjackingProtection: Bool
    /// When true, POST/DELETE requests to `/api/controllarr/*` require an
    /// `X-CSRF-Token` header matching the session's token.
    public var csrfProtection: Bool

    public init(
        allowlistEnabled: Bool = false,
        allowedCIDRs: [String] = [],
        clickjackingProtection: Bool = true,
        csrfProtection: Bool = false
    ) {
        self.allowlistEnabled = allowlistEnabled
        self.allowedCIDRs = allowedCIDRs
        self.clickjackingProtection = clickjackingProtection
        self.csrfProtection = csrfProtection
    }
}

/// Native app UI behavior (menu-bar integration, window defaults, table
/// column widths, saved filters). Serializable so the Mac app and daemon
/// can share preferences across restarts.
public struct UIPreferences: Codable, Sendable, Equatable {
    /// Show the menu-bar status item. When true, closing the window hides
    /// it to the menu bar instead of quitting.
    public var menuBarEnabled: Bool
    /// Launch with the main window hidden (menu-bar only).
    public var startMinimized: Bool
    /// Close the main window to the menu bar instead of quitting.
    public var closeToMenuBar: Bool
    /// Saved torrent-table column widths. Keyed by column id.
    public var torrentColumnWidths: [String: Double]
    /// Persisted torrent sort key and direction. Nil = name ascending.
    public var torrentSortKey: String?
    public var torrentSortAscending: Bool
    /// Last-selected torrent status filter.
    public var torrentStatusFilter: String
    /// Last-selected torrent category filter. Empty string = "all
    /// categories"; the sentinel `"__none__"` = "uncategorized only";
    /// any other value matches torrents whose assigned category name
    /// exactly equals this string.
    public var torrentCategoryFilter: String

    public init(
        menuBarEnabled: Bool = true,
        startMinimized: Bool = false,
        closeToMenuBar: Bool = false,
        torrentColumnWidths: [String: Double] = [:],
        torrentSortKey: String? = nil,
        torrentSortAscending: Bool = true,
        torrentStatusFilter: String = "all",
        torrentCategoryFilter: String = ""
    ) {
        self.menuBarEnabled = menuBarEnabled
        self.startMinimized = startMinimized
        self.closeToMenuBar = closeToMenuBar
        self.torrentColumnWidths = torrentColumnWidths
        self.torrentSortKey = torrentSortKey
        self.torrentSortAscending = torrentSortAscending
        self.torrentStatusFilter = torrentStatusFilter
        self.torrentCategoryFilter = torrentCategoryFilter
    }

    // Custom decoder so adding new fields doesn't break forward-compat
    // with older state.json files that don't carry every key yet.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.menuBarEnabled = try c.decodeIfPresent(Bool.self, forKey: .menuBarEnabled) ?? true
        self.startMinimized = try c.decodeIfPresent(Bool.self, forKey: .startMinimized) ?? false
        self.closeToMenuBar = try c.decodeIfPresent(Bool.self, forKey: .closeToMenuBar) ?? false
        self.torrentColumnWidths = try c.decodeIfPresent([String: Double].self, forKey: .torrentColumnWidths) ?? [:]
        self.torrentSortKey = try c.decodeIfPresent(String.self, forKey: .torrentSortKey)
        self.torrentSortAscending = try c.decodeIfPresent(Bool.self, forKey: .torrentSortAscending) ?? true
        self.torrentStatusFilter = try c.decodeIfPresent(String.self, forKey: .torrentStatusFilter) ?? "all"
        self.torrentCategoryFilter = try c.decodeIfPresent(String.self, forKey: .torrentCategoryFilter) ?? ""
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

public struct ArrEndpoint: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case sonarr
        case radarr
    }
    public var kind: Kind
    public var baseURL: String
    /// When true, the API key lives in Keychain under "arr_<name>".
    /// The `apiKey` field below is only used for initial setup / migration.
    public var apiKeyInKeychain: Bool
    /// Plaintext API key — only used during initial setup. Once migrated
    /// to Keychain this is cleared to empty.
    public var apiKey: String

    public init(
        name: String,
        kind: Kind,
        baseURL: String,
        apiKeyInKeychain: Bool = false,
        apiKey: String = ""
    ) {
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.apiKeyInKeychain = apiKeyInKeychain
        self.apiKey = apiKey
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
    /// Policy-driven recovery rules for active health issues.
    public var recoveryRules: [RecoveryRule]

    // Bandwidth scheduler -------------------------------------------------------

    /// Time-of-day bandwidth limit windows. First matching window wins.
    public var bandwidthSchedule: [BandwidthRule]

    // Disk space monitor --------------------------------------------------------

    /// Minimum free disk space in GB before auto-pausing downloads.
    /// nil or 0 = disabled.
    public var diskSpaceMinimumGB: Int?
    /// Path to monitor for free space. Defaults to `defaultSavePath`.
    /// If empty, uses `defaultSavePath`.
    public var diskSpaceMonitorPath: String

    // VPN protection ---------------------------------------------------------------

    /// Master toggle: when true, VPNMonitor actively detects and binds
    /// to the VPN network interface.
    public var vpnEnabled: Bool
    /// When true and VPN drops, all torrents are paused immediately.
    public var vpnKillSwitch: Bool
    /// When true, libtorrent's outgoing_interfaces and listen_interfaces
    /// are bound to the VPN adapter so no traffic leaks to the default
    /// route.
    public var vpnBindInterface: Bool
    /// Interface name prefix to detect the VPN tunnel (e.g. "utun" for
    /// PIA, WireGuard, and most macOS VPN clients).
    public var vpnInterfacePrefix: String
    /// How often (in seconds) the monitor checks for VPN status.
    public var vpnMonitorIntervalSeconds: Int

    // *arr integration ----------------------------------------------------------

    /// Connected Sonarr / Radarr endpoints for proactive re-search.
    public var arrEndpoints: [ArrEndpoint]
    /// Hours a torrent must be stalled before the *arr notifier triggers
    /// a re-search. Avoids false positives on slow starts.
    public var arrReSearchAfterHours: Int

    // Peer discovery ------------------------------------------------------------

    /// DHT/PeX/LSD toggles applied to libtorrent on startup and whenever
    /// settings are saved.
    public var peerDiscovery: PeerDiscovery

    // Connection limits --------------------------------------------------------

    public var connectionLimits: ConnectionLimits

    // WebUI security ----------------------------------------------------------

    public var webUISecurity: WebUISecurity

    // UI preferences ----------------------------------------------------------

    public var uiPreferences: UIPreferences

    /// When the user switches a torrent's category to one with a different
    /// save path, should Controllarr move the files automatically?
    /// "ask" = confirm (native UI) / no-op (WebUI & *arr); "always" = always
    /// move; "never" = never move.
    public var categoryChangeMove: CategoryMovePolicy

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
            recoveryRules: [],
            bandwidthSchedule: [],
            vpnEnabled: false,
            vpnKillSwitch: true,
            vpnBindInterface: true,
            vpnInterfacePrefix: "utun",
            vpnMonitorIntervalSeconds: 5,
            diskSpaceMinimumGB: nil,
            diskSpaceMonitorPath: "",
            arrEndpoints: [],
            arrReSearchAfterHours: 6,
            peerDiscovery: PeerDiscovery(),
            connectionLimits: ConnectionLimits(),
            webUISecurity: WebUISecurity(),
            uiPreferences: UIPreferences(),
            categoryChangeMove: .ask
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
        self.recoveryRules = try c.decodeIfPresent([RecoveryRule].self, forKey: .recoveryRules) ?? []
        self.bandwidthSchedule = try c.decodeIfPresent([BandwidthRule].self, forKey: .bandwidthSchedule) ?? []
        self.vpnEnabled = try c.decodeIfPresent(Bool.self, forKey: .vpnEnabled) ?? false
        self.vpnKillSwitch = try c.decodeIfPresent(Bool.self, forKey: .vpnKillSwitch) ?? true
        self.vpnBindInterface = try c.decodeIfPresent(Bool.self, forKey: .vpnBindInterface) ?? true
        self.vpnInterfacePrefix = try c.decodeIfPresent(String.self, forKey: .vpnInterfacePrefix) ?? "utun"
        self.vpnMonitorIntervalSeconds = try c.decodeIfPresent(Int.self, forKey: .vpnMonitorIntervalSeconds) ?? 5
        self.diskSpaceMinimumGB = try c.decodeIfPresent(Int.self, forKey: .diskSpaceMinimumGB)
        self.diskSpaceMonitorPath = try c.decodeIfPresent(String.self, forKey: .diskSpaceMonitorPath) ?? ""
        self.arrEndpoints = try c.decodeIfPresent([ArrEndpoint].self, forKey: .arrEndpoints) ?? []
        self.arrReSearchAfterHours = try c.decodeIfPresent(Int.self, forKey: .arrReSearchAfterHours) ?? 6
        self.peerDiscovery = try c.decodeIfPresent(PeerDiscovery.self, forKey: .peerDiscovery) ?? PeerDiscovery()
        self.connectionLimits = try c.decodeIfPresent(ConnectionLimits.self, forKey: .connectionLimits) ?? ConnectionLimits()
        self.webUISecurity = try c.decodeIfPresent(WebUISecurity.self, forKey: .webUISecurity) ?? WebUISecurity()
        self.uiPreferences = try c.decodeIfPresent(UIPreferences.self, forKey: .uiPreferences) ?? UIPreferences()
        self.categoryChangeMove = try c.decodeIfPresent(CategoryMovePolicy.self, forKey: .categoryChangeMove) ?? .ask
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
        recoveryRules: [RecoveryRule] = [],
        bandwidthSchedule: [BandwidthRule] = [],
        vpnEnabled: Bool = false,
        vpnKillSwitch: Bool = true,
        vpnBindInterface: Bool = true,
        vpnInterfacePrefix: String = "utun",
        vpnMonitorIntervalSeconds: Int = 5,
        diskSpaceMinimumGB: Int? = nil,
        diskSpaceMonitorPath: String = "",
        arrEndpoints: [ArrEndpoint] = [],
        arrReSearchAfterHours: Int = 6,
        peerDiscovery: PeerDiscovery = PeerDiscovery(),
        connectionLimits: ConnectionLimits = ConnectionLimits(),
        webUISecurity: WebUISecurity = WebUISecurity(),
        uiPreferences: UIPreferences = UIPreferences(),
        categoryChangeMove: CategoryMovePolicy = .ask
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
        self.recoveryRules = recoveryRules
        self.bandwidthSchedule = bandwidthSchedule
        self.vpnEnabled = vpnEnabled
        self.vpnKillSwitch = vpnKillSwitch
        self.vpnBindInterface = vpnBindInterface
        self.vpnInterfacePrefix = vpnInterfacePrefix
        self.vpnMonitorIntervalSeconds = vpnMonitorIntervalSeconds
        self.diskSpaceMinimumGB = diskSpaceMinimumGB
        self.diskSpaceMonitorPath = diskSpaceMonitorPath
        self.arrEndpoints = arrEndpoints
        self.arrReSearchAfterHours = arrReSearchAfterHours
        self.peerDiscovery = peerDiscovery
        self.connectionLimits = connectionLimits
        self.webUISecurity = webUISecurity
        self.uiPreferences = uiPreferences
        self.categoryChangeMove = categoryChangeMove
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

public enum BackupError: Error, LocalizedError, Sendable, Equatable {
    case unsupportedFormat(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let version):
            return "Unsupported backup format version \(version)."
        }
    }
}

public struct BackupSecrets: Codable, Sendable, Equatable {
    public var webUIPassword: String?
    public var arrAPIKeys: [String: String]

    public init(webUIPassword: String? = nil, arrAPIKeys: [String: String] = [:]) {
        self.webUIPassword = webUIPassword
        self.arrAPIKeys = arrAPIKeys
    }
}

public struct BackupArchive: Codable, Sendable, Equatable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var createdAt: Date
    public var state: PersistedState
    public var secrets: BackupSecrets?

    public init(
        formatVersion: Int = BackupArchive.currentFormatVersion,
        createdAt: Date = Date(),
        state: PersistedState,
        secrets: BackupSecrets? = nil
    ) {
        self.formatVersion = formatVersion
        self.createdAt = createdAt
        self.state = state
        self.secrets = secrets
    }
}

public struct BackupRestoreResult: Codable, Sendable, Equatable {
    public var restoredAt: Date
    public var categoryCount: Int
    public var endpointCount: Int
    public var includedSecrets: Bool
    public var restartRecommended: Bool

    public init(
        restoredAt: Date = Date(),
        categoryCount: Int,
        endpointCount: Int,
        includedSecrets: Bool,
        restartRecommended: Bool
    ) {
        self.restoredAt = restoredAt
        self.categoryCount = categoryCount
        self.endpointCount = endpointCount
        self.includedSecrets = includedSecrets
        self.restartRecommended = restartRecommended
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

        // One-time migration: move plaintext password into Keychain.
        // Inlined here because actor init is nonisolated in Swift 6 and
        // we can only access stored properties directly (no actor-isolated
        // method calls).
        let pwd = state.settings.webUIPassword
        if !pwd.isEmpty && pwd != "__keychain__" {
            Keychain.set(pwd, forKey: Keychain.webUIPasswordKey)
            state.settings.webUIPassword = "__keychain__"
            _needsFlush = true
        }
        for i in state.settings.arrEndpoints.indices {
            let ep = state.settings.arrEndpoints[i]
            if !ep.apiKey.isEmpty && !ep.apiKeyInKeychain {
                Keychain.set(ep.apiKey, forKey: "arr_\(ep.name)")
                state.settings.arrEndpoints[i].apiKey = ""
                state.settings.arrEndpoints[i].apiKeyInKeychain = true
                _needsFlush = true
            }
        }
        // Deferred flush — actor isn't fully initialized yet so
        // scheduleFlush() can't be called; the first mutation after
        // init (or flushNow on shutdown) will persist the migrated state.
    }

    /// Flag set during init when migration happened. The first call to
    /// any write method will trigger the actual disk write.
    private var _needsFlush: Bool = false

    /// Call once after init from an async context to flush any migration
    /// changes that happened during init.
    public func flushMigrationIfNeeded() {
        if _needsFlush {
            _needsFlush = false
            scheduleFlush()
        }
    }

    // MARK: Credential helpers

    /// Returns the actual WebUI password (from Keychain if migrated,
    /// fallback to the JSON field for pre-migration state files).
    public func resolvedWebUIPassword() -> String {
        if state.settings.webUIPassword == "__keychain__" {
            return Keychain.get(forKey: Keychain.webUIPasswordKey) ?? ""
        }
        return state.settings.webUIPassword
    }

    /// Store a new WebUI password in Keychain and mark the JSON sentinel.
    public func setWebUIPassword(_ password: String) {
        Keychain.set(password, forKey: Keychain.webUIPasswordKey)
        state.settings.webUIPassword = "__keychain__"
        scheduleFlush()
    }

    /// Retrieve the API key for a named *arr endpoint from Keychain.
    public func arrAPIKey(forEndpoint name: String) -> String {
        Keychain.get(forKey: "arr_\(name)") ?? ""
    }

    /// Store an API key for a named *arr endpoint in Keychain.
    public func setArrAPIKey(_ key: String, forEndpoint name: String) {
        Keychain.set(key, forKey: "arr_\(name)")
        // Mark the endpoint as migrated.
        if let i = state.settings.arrEndpoints.firstIndex(where: { $0.name == name }) {
            state.settings.arrEndpoints[i].apiKeyInKeychain = true
            state.settings.arrEndpoints[i].apiKey = ""
            scheduleFlush()
        }
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

    public func exportBackup(includeSecrets: Bool) -> BackupArchive {
        let secrets: BackupSecrets?
        if includeSecrets {
            var arrAPIKeys: [String: String] = [:]
            for endpoint in state.settings.arrEndpoints {
                let key = Keychain.get(forKey: "arr_\(endpoint.name)") ?? ""
                if !key.isEmpty {
                    arrAPIKeys[endpoint.name] = key
                }
            }
            let password = resolvedWebUIPassword()
            secrets = BackupSecrets(
                webUIPassword: password.isEmpty ? nil : password,
                arrAPIKeys: arrAPIKeys
            )
        } else {
            secrets = nil
        }

        return BackupArchive(state: state, secrets: secrets)
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

    public func restoreBackup(_ backup: BackupArchive) throws -> BackupRestoreResult {
        guard (1...BackupArchive.currentFormatVersion).contains(backup.formatVersion) else {
            throw BackupError.unsupportedFormat(backup.formatVersion)
        }

        let previousSettings = state.settings
        var restoredState = backup.state

        if let password = backup.secrets?.webUIPassword, !password.isEmpty {
            Keychain.set(password, forKey: Keychain.webUIPasswordKey)
            restoredState.settings.webUIPassword = "__keychain__"
        } else if !restoredState.settings.webUIPassword.isEmpty,
                  restoredState.settings.webUIPassword != "__keychain__" {
            Keychain.set(restoredState.settings.webUIPassword, forKey: Keychain.webUIPasswordKey)
            restoredState.settings.webUIPassword = "__keychain__"
        }

        for index in restoredState.settings.arrEndpoints.indices {
            let endpoint = restoredState.settings.arrEndpoints[index]
            if let apiKey = backup.secrets?.arrAPIKeys[endpoint.name], !apiKey.isEmpty {
                Keychain.set(apiKey, forKey: "arr_\(endpoint.name)")
                restoredState.settings.arrEndpoints[index].apiKeyInKeychain = true
                restoredState.settings.arrEndpoints[index].apiKey = ""
            } else if !endpoint.apiKey.isEmpty {
                Keychain.set(endpoint.apiKey, forKey: "arr_\(endpoint.name)")
                restoredState.settings.arrEndpoints[index].apiKeyInKeychain = true
                restoredState.settings.arrEndpoints[index].apiKey = ""
            }
        }

        state = restoredState
        scheduleFlush()

        return BackupRestoreResult(
            categoryCount: restoredState.categories.count,
            endpointCount: restoredState.settings.arrEndpoints.count,
            includedSecrets: backup.secrets != nil,
            restartRecommended:
                previousSettings.webUIHost != restoredState.settings.webUIHost
                || previousSettings.webUIPort != restoredState.settings.webUIPort
        )
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

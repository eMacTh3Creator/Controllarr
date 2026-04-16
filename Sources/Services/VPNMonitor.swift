//
//  VPNMonitor.swift
//  Controllarr
//
//  Detects VPN tunnel interfaces (e.g. utun* from PIA, WireGuard, etc.)
//  and enforces two protective behaviours:
//
//  1. **Kill switch** — if the VPN goes down, all non-paused torrents are
//     immediately paused. When the VPN comes back they are resumed.
//  2. **Interface binding** — libtorrent's outgoing_interfaces and
//     listen_interfaces are set to the VPN adapter so no traffic ever
//     leaks through the default route.
//
//  Interface detection uses the POSIX getifaddrs() API which is always
//  available on macOS — no SystemConfiguration dependency needed.
//

import Foundation
#if canImport(Darwin)
import Darwin
#endif
import TorrentEngine
import Persistence

public actor VPNMonitor {

    // MARK: - Public types

    public struct Status: Sendable {
        /// Whether the VPN protection feature is enabled in settings.
        public let enabled: Bool
        /// Whether a matching VPN interface was found.
        public let isConnected: Bool
        /// The name of the detected VPN interface (e.g. "utun4").
        public let interfaceName: String?
        /// The IP address assigned to the VPN interface.
        public let interfaceIP: String?
        /// True when the kill switch has engaged (VPN down + torrents paused).
        public let killSwitchEngaged: Bool
        /// Hashes of torrents paused by the kill switch.
        public let pausedHashes: Set<String>
        /// True when libtorrent is bound to the VPN adapter.
        public let boundToVPN: Bool
    }

    /// Describes a detected VPN tunnel interface.
    struct DetectedInterface: Sendable {
        let name: String  // e.g. "utun4"
        let ip: String    // e.g. "10.47.0.1"
    }

    // MARK: - Dependencies

    private let engine: TorrentEngine
    private let store: PersistenceStore
    private let logger: Logger
    private var task: Task<Void, Never>?

    // MARK: - State

    /// Hashes that **we** paused via the kill switch. Only these get
    /// auto-resumed when VPN reconnects.
    private var pausedByUs: Set<String> = []
    private var killSwitchEngaged: Bool = false
    private var currentInterface: DetectedInterface?
    private var isBound: Bool = false

    public init(engine: TorrentEngine, store: PersistenceStore, logger: Logger) {
        self.engine = engine
        self.store = store
        self.logger = logger
    }

    // MARK: - Lifecycle

    public func start() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.evaluate()
                let interval = await self?.currentInterval() ?? 5
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    public func snapshot() -> Status {
        Status(
            enabled: true, // caller should check settings; snapshot just reports state
            isConnected: currentInterface != nil,
            interfaceName: currentInterface?.name,
            interfaceIP: currentInterface?.ip,
            killSwitchEngaged: killSwitchEngaged,
            pausedHashes: pausedByUs,
            boundToVPN: isBound
        )
    }

    /// Force an immediate re-evaluation (e.g. after settings change).
    public func forceEvaluate() async {
        await evaluate()
    }

    // MARK: - Core evaluation loop

    private func evaluate() async {
        let settings = await store.settings()

        // Feature disabled — make sure we're unbound and kill switch disarmed.
        guard settings.vpnEnabled else {
            if killSwitchEngaged {
                await resumeKillSwitched()
                killSwitchEngaged = false
                logger.info("vpn", "VPN protection disabled — resumed kill-switched torrents")
            }
            if isBound {
                await unbindFromVPN()
                isBound = false
                logger.info("vpn", "VPN protection disabled — unbound from VPN interface")
            }
            currentInterface = nil
            return
        }

        let prefix = settings.vpnInterfacePrefix.isEmpty ? "utun" : settings.vpnInterfacePrefix
        let detected = Self.detectVPNInterface(prefix: prefix)

        if let iface = detected {
            // VPN is up.
            let changed = (iface.name != currentInterface?.name || iface.ip != currentInterface?.ip)
            currentInterface = iface

            // If kill switch was engaged, resume.
            if killSwitchEngaged {
                await resumeKillSwitched()
                killSwitchEngaged = false
                logger.info("vpn", "VPN reconnected (\(iface.name) / \(iface.ip)) — resumed \(pausedByUs.count) torrents")
                pausedByUs.removeAll()
            }

            // Bind to VPN interface if enabled and (first time or interface changed).
            if settings.vpnBindInterface && (!isBound || changed) {
                await bindToVPN(iface: iface)
                isBound = true
                logger.info("vpn", "Bound to VPN interface \(iface.name) (\(iface.ip))")
            }
        } else {
            // VPN is down.
            currentInterface = nil

            // Engage kill switch if enabled.
            if settings.vpnKillSwitch && !killSwitchEngaged {
                await engageKillSwitch()
                killSwitchEngaged = true
            }

            // Unbind from VPN so libtorrent doesn't try to use a dead interface.
            if isBound {
                await unbindFromVPN()
                isBound = false
                logger.warn("vpn", "VPN down — unbound from interface")
            }
        }
    }

    private func currentInterval() async -> Int {
        let settings = await store.settings()
        return max(1, settings.vpnMonitorIntervalSeconds)
    }

    // MARK: - Kill switch

    private func engageKillSwitch() async {
        let torrents = await engine.pollStats()
        var count = 0
        for t in torrents where !t.paused {
            _ = await engine.pause(infoHash: t.infoHash)
            pausedByUs.insert(t.infoHash)
            count += 1
        }
        logger.warn("vpn", "Kill switch engaged — paused \(count) torrents")
    }

    private func resumeKillSwitched() async {
        for hash in pausedByUs {
            _ = await engine.resume(infoHash: hash)
        }
        pausedByUs.removeAll()
    }

    // MARK: - Interface binding

    private func bindToVPN(iface: DetectedInterface) async {
        let listenPort = await engine.listenPort
        // Bind outgoing connections to the VPN interface name.
        await engine.setOutgoingInterface(iface.name)
        // Bind listen to the VPN IP + current port (IPv4 only for tunnel).
        await engine.setListenInterfaces("\(iface.ip):\(listenPort)")
    }

    private func unbindFromVPN() async {
        let listenPort = await engine.listenPort
        // Revert to wildcard binding.
        await engine.setOutgoingInterface("")
        await engine.setListenInterfaces("0.0.0.0:\(listenPort),[::]:\(listenPort)")
    }

    // MARK: - VPN interface detection (POSIX getifaddrs)

    /// Scan network interfaces for one matching the given prefix that has
    /// an assigned IPv4 address. Returns the first match.
    static func detectVPNInterface(prefix: String) -> DetectedInterface? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else {
            return nil
        }
        defer { freeifaddrs(ifaddrPtr) }

        var current: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = current {
            defer { current = addr.pointee.ifa_next }

            let name = String(cString: addr.pointee.ifa_name)
            guard name.hasPrefix(prefix) else { continue }

            // Interface must be up and running.
            let flags = Int32(addr.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_RUNNING) != 0 else { continue }

            guard let sockaddr = addr.pointee.ifa_addr else { continue }

            // We only care about IPv4 for tunnel interfaces.
            if sockaddr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(
                    sockaddr,
                    socklen_t(sockaddr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil, 0,
                    NI_NUMERICHOST
                )
                if result == 0 {
                    let ip = String(cString: hostname)
                    // Skip link-local and loopback.
                    if ip.hasPrefix("127.") || ip.hasPrefix("169.254.") { continue }
                    return DetectedInterface(name: name, ip: ip)
                }
            }
        }
        return nil
    }
}

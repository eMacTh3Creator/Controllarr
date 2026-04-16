//
//  NetworkDiagnostics.swift
//  Controllarr
//
//  Shared runtime snapshot that explains how the WebUI/API is exposed on
//  the local network and how that relates to the VPN-bound torrent engine.
//

import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum NetworkDiagnostics {

    public struct LANInterface: Sendable, Codable, Equatable, Identifiable {
        public var id: String { "\(name)-\(ip)" }
        public let name: String
        public let ip: String
    }

    public struct Snapshot: Sendable, Codable, Equatable {
        public let bindHost: String
        public let bindPort: Int
        public let localOpenURL: String
        public let remoteAccessConfigured: Bool
        public let lanInterfaces: [LANInterface]
        public let suggestedRemoteURLs: [String]
        public let recommendedRemoteURL: String?
        public let vpnConnected: Bool
        public let vpnInterfaceName: String?
        public let vpnInterfaceIP: String?
        public let vpnBoundToTorrentEngine: Bool
        public let warning: String?
    }

    public static func snapshot(
        bindHost: String,
        bindPort: Int,
        vpnStatus: VPNMonitor.Status?
    ) -> Snapshot {
        evaluate(
            bindHost: bindHost,
            bindPort: bindPort,
            interfaces: detectLANInterfaces(),
            vpnStatus: vpnStatus
        )
    }

    static func evaluate(
        bindHost: String,
        bindPort: Int,
        interfaces: [LANInterface],
        vpnStatus: VPNMonitor.Status?
    ) -> Snapshot {
        let cleanedHost = normalizedHost(bindHost)
        let sortedInterfaces = interfaces.sorted { lhs, rhs in
            interfaceSortKey(lhs.name, lhs.ip) < interfaceSortKey(rhs.name, rhs.ip)
        }
        let localOpenHost = localHostForOpen(cleanedHost)
        let remoteAccessConfigured: Bool
        if isWildcardHost(cleanedHost) {
            remoteAccessConfigured = true
        } else if isLoopbackHost(cleanedHost) || cleanedHost.isEmpty {
            remoteAccessConfigured = false
        } else {
            remoteAccessConfigured = sortedInterfaces.contains(where: { $0.ip == cleanedHost })
        }

        let suggestedRemoteURLs = remoteAccessConfigured
            ? sortedInterfaces.map { "http://\($0.ip):\(bindPort)/" }
            : []

        let warning: String?
        if !remoteAccessConfigured {
            warning = "Remote LAN access is not configured. Bind the WebUI to 0.0.0.0 or one of this Mac's LAN IPs, then restart Controllarr."
        } else if vpnStatus?.isConnected == true {
            warning = "Controllarr is configured for LAN access and torrent traffic is already bound separately to the VPN adapter. If remote clients still cannot connect while the VPN is on, the VPN client is probably blocking inbound LAN traffic."
        } else {
            warning = nil
        }

        return Snapshot(
            bindHost: cleanedHost,
            bindPort: bindPort,
            localOpenURL: "http://\(localOpenHost):\(bindPort)/",
            remoteAccessConfigured: remoteAccessConfigured,
            lanInterfaces: sortedInterfaces,
            suggestedRemoteURLs: suggestedRemoteURLs,
            recommendedRemoteURL: suggestedRemoteURLs.first,
            vpnConnected: vpnStatus?.isConnected == true,
            vpnInterfaceName: vpnStatus?.interfaceName,
            vpnInterfaceIP: vpnStatus?.interfaceIP,
            vpnBoundToTorrentEngine: vpnStatus?.boundToVPN == true,
            warning: warning
        )
    }

    static func detectLANInterfaces() -> [LANInterface] {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else {
            return []
        }
        defer { freeifaddrs(ifaddrPtr) }

        var interfaces: [String: LANInterface] = [:]
        var current: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = current {
            defer { current = addr.pointee.ifa_next }

            let name = String(cString: addr.pointee.ifa_name)
            guard !name.hasPrefix("utun"),
                  !name.hasPrefix("lo"),
                  let sockaddr = addr.pointee.ifa_addr,
                  sockaddr.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let flags = Int32(addr.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0,
                  (flags & IFF_RUNNING) != 0,
                  (flags & IFF_LOOPBACK) == 0 else {
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                sockaddr,
                socklen_t(sockaddr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil, 0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }

            let bytes = hostname.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            guard let ip = String(bytes: bytes, encoding: .utf8) else { continue }
            guard isPrivateLANAddress(ip) else { continue }
            let interface = LANInterface(name: name, ip: ip)
            interfaces[interface.id] = interface
        }

        return Array(interfaces.values)
    }

    public static func normalizedHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func localHostForOpen(_ bindHost: String) -> String {
        if isWildcardHost(bindHost) || bindHost.isEmpty {
            return "127.0.0.1"
        }
        return bindHost
    }

    static func isWildcardHost(_ host: String) -> Bool {
        host == "0.0.0.0" || host == "::" || host == "[::]"
    }

    static func isLoopbackHost(_ host: String) -> Bool {
        host == "127.0.0.1" || host == "localhost" || host == "::1" || host == "[::1]"
    }

    private static func isPrivateLANAddress(_ ip: String) -> Bool {
        let octets = ip.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        if octets[0] == 10 { return true }
        if octets[0] == 192 && octets[1] == 168 { return true }
        if octets[0] == 172 && (16...31).contains(octets[1]) { return true }
        return false
    }

    private static func interfaceSortKey(_ name: String, _ ip: String) -> String {
        let prefixRank: Int
        switch true {
        case name.hasPrefix("en"): prefixRank = 0
        case name.hasPrefix("bridge"): prefixRank = 1
        default: prefixRank = 2
        }
        return "\(prefixRank)-\(name)-\(ip)"
    }
}

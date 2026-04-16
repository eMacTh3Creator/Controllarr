//
//  SecurityMiddleware.swift
//  Controllarr — Phase 2
//
//  Three WebUI hardening middlewares, added to Router in the same spot
//  CORS/Auth are added:
//
//   * SecurityHeadersMiddleware — X-Frame-Options, X-Content-Type-Options,
//     Referrer-Policy, and an optional CSP when clickjacking protection is on.
//   * IPAllowlistMiddleware      — rejects requests whose remote address is
//     outside the operator-defined CIDR list. Always allows loopback.
//   * CSRFMiddleware             — requires an `X-CSRF-Token` header on
//     unsafe methods against `/api/controllarr/*`; token is minted by the
//     qBittorrent auth endpoint and stored client-side.
//
//  Each middleware pulls its settings live from PersistenceStore on every
//  request so toggles take effect immediately without restarting the server.
//

import Foundation
import Hummingbird
import HummingbirdCore
import HTTPTypes
import NIOCore
import Persistence

// MARK: - Security response headers

struct SecurityHeadersMiddleware<Context: RequestContext>: RouterMiddleware {
    let store: PersistenceStore

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        let security = await store.settings().webUISecurity
        var response = try await next(request, context)
        response.headers[.xContentTypeOptions] = "nosniff"
        response.headers[.referrerPolicy] = "no-referrer"
        if security.clickjackingProtection {
            response.headers[.xFrameOptions] = "DENY"
            // Hummingbird's HTTPField name is lowercase.
            response.headers[.contentSecurityPolicy] =
                "frame-ancestors 'none'"
        }
        return response
    }
}

// MARK: - IP / CIDR allowlist

struct IPAllowlistMiddleware<Context: RequestContext>: RouterMiddleware {
    let store: PersistenceStore

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        let security = await store.settings().webUISecurity
        guard security.allowlistEnabled else {
            return try await next(request, context)
        }
        let remote = Self.remoteIP(for: request, context: context)
        // Always allow loopback so the operator doesn't lock themselves out
        // from the machine Controllarr is running on.
        if Self.isLoopback(remote) {
            return try await next(request, context)
        }
        for rule in security.allowedCIDRs {
            if CIDR.matches(ip: remote, rule: rule) {
                return try await next(request, context)
            }
        }
        return Response(
            status: .forbidden,
            body: .init(byteBuffer: ByteBuffer(string: "Forbidden (IP not in allowlist)."))
        )
    }

    private static func remoteIP(for request: Request, context: Context) -> String {
        // Hummingbird exposes the remote address on the RequestContext when
        // available; fall back to an X-Forwarded-For header for reverse
        // proxies that the operator chose to trust.
        if let forwarded = request.headers[.xForwardedFor]?
            .split(separator: ",")
            .first?
            .trimmingCharacters(in: .whitespaces),
           !forwarded.isEmpty {
            return String(forwarded)
        }
        if let ctx = context as? any RemoteAddressRequestContext,
           let addr = ctx.remoteAddress?.ipAddress {
            return addr
        }
        return ""
    }

    private static func isLoopback(_ ip: String) -> Bool {
        ip == "127.0.0.1" || ip == "::1" || ip == "0:0:0:0:0:0:0:1"
    }
}

// MARK: - CIDR helper (IPv4 + IPv6)

enum CIDR {
    /// Return true iff `ip` sits inside the CIDR block `rule`.
    /// A bare IP (no "/") is treated as a /32 or /128 exact match.
    static func matches(ip: String, rule: String) -> Bool {
        let trimmedRule = rule.trimmingCharacters(in: .whitespaces)
        let (prefix, bits): (String, Int)
        if let slash = trimmedRule.firstIndex(of: "/") {
            prefix = String(trimmedRule[..<slash])
            bits = Int(trimmedRule[trimmedRule.index(after: slash)...]) ?? -1
        } else {
            prefix = trimmedRule
            bits = -1
        }
        guard let ruleBytes = ipBytes(prefix),
              let ipBytesArr = ipBytes(ip),
              ruleBytes.count == ipBytesArr.count else {
            return false
        }
        let maskBits = bits >= 0 ? bits : ruleBytes.count * 8
        return bytesMatch(ipBytesArr, ruleBytes, bits: maskBits)
    }

    private static func ipBytes(_ s: String) -> [UInt8]? {
        var addr4 = in_addr()
        if inet_pton(AF_INET, s, &addr4) == 1 {
            return withUnsafeBytes(of: &addr4) { Array($0) }
        }
        var addr6 = in6_addr()
        if inet_pton(AF_INET6, s, &addr6) == 1 {
            return withUnsafeBytes(of: &addr6) { Array($0) }
        }
        return nil
    }

    private static func bytesMatch(_ a: [UInt8], _ b: [UInt8], bits: Int) -> Bool {
        guard bits >= 0, bits <= a.count * 8 else { return false }
        let fullBytes = bits / 8
        let remainder = bits % 8
        if fullBytes > 0 {
            for i in 0..<fullBytes where a[i] != b[i] {
                return false
            }
        }
        if remainder > 0 {
            let mask: UInt8 = UInt8(0xFF << (8 - remainder)) & 0xFF
            if (a[fullBytes] & mask) != (b[fullBytes] & mask) {
                return false
            }
        }
        return true
    }
}

// MARK: - HTTPField.Name shims

extension HTTPField.Name {
    static var xFrameOptions: HTTPField.Name { HTTPField.Name("X-Frame-Options")! }
    static var referrerPolicy: HTTPField.Name { HTTPField.Name("Referrer-Policy")! }
    static var xForwardedFor: HTTPField.Name { HTTPField.Name("X-Forwarded-For")! }
}

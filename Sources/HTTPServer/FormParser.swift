//
//  FormParser.swift
//  Controllarr — Phase 1
//
//  Minimal urlencoded form parser + multipart parser. Covers exactly what
//  the qBittorrent API needs; anything else is out of scope.
//

import Foundation
import NIOCore

enum FormParser {

    /// Parse a `application/x-www-form-urlencoded` body.
    static func parse(_ buffer: ByteBuffer) -> [String: String] {
        var buf = buffer
        let raw = buf.readString(length: buf.readableBytes) ?? ""
        return parseQuery(raw)
    }

    /// Parse a URL query string or urlencoded form into a dictionary.
    /// Repeated keys keep the last value, which matches qBit's API.
    static func parseQuery(_ raw: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in raw.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(parts.first ?? "").removingPercentEncoding ?? ""
            let value: String
            if parts.count == 2 {
                value = String(parts[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
            } else {
                value = ""
            }
            if !key.isEmpty { out[key] = value }
        }
        return out
    }
}

// MARK: - Multipart

struct MultipartPart {
    let name: String
    let filename: String?
    let body: [UInt8]
}

enum MultipartParser {

    /// Parse `multipart/form-data` into parts. Does not support nested
    /// multipart; that's fine for what the qBit API needs.
    static func parse(body: ByteBuffer, contentType: String) -> [MultipartPart] {
        guard let boundary = extractBoundary(contentType) else { return [] }
        var buf = body
        guard let data = buf.readBytes(length: buf.readableBytes) else { return [] }

        let delim = "--\(boundary)"
        let delimBytes = Array(delim.utf8)
        let crlf: [UInt8] = [0x0D, 0x0A]

        // Split the payload on the delimiter.
        var parts: [[UInt8]] = []
        var start = 0
        while start < data.count {
            guard let idx = range(of: delimBytes, in: data, from: start) else { break }
            if idx > start {
                parts.append(Array(data[start..<idx]))
            }
            start = idx + delimBytes.count
            // Skip trailing CRLF after the delimiter (or `--` for the last one).
            if start + 1 < data.count && data[start] == 0x0D && data[start + 1] == 0x0A {
                start += 2
            }
        }

        // Trim the leading empty chunk and the trailing "--" closer.
        var result: [MultipartPart] = []
        for chunk in parts {
            // Each part is: headers CRLF CRLF body CRLF
            guard let hdrEnd = range(of: [0x0D, 0x0A, 0x0D, 0x0A], in: chunk, from: 0) else { continue }
            let headerBytes = chunk[0..<hdrEnd]
            var bodyBytes = chunk[(hdrEnd + 4)..<chunk.count]
            // Strip trailing CRLF that precedes the next delimiter.
            if bodyBytes.count >= 2
               && bodyBytes[bodyBytes.index(bodyBytes.endIndex, offsetBy: -2)] == 0x0D
               && bodyBytes[bodyBytes.index(bodyBytes.endIndex, offsetBy: -1)] == 0x0A {
                bodyBytes = bodyBytes[bodyBytes.startIndex..<bodyBytes.index(bodyBytes.endIndex, offsetBy: -2)]
            }

            let headerString = String(decoding: headerBytes, as: UTF8.self)
            guard let disposition = headerString
                .split(whereSeparator: { $0 == "\r" || $0 == "\n" })
                .first(where: { $0.lowercased().hasPrefix("content-disposition") }) else {
                continue
            }
            let (name, filename) = parseContentDisposition(String(disposition))
            if let name {
                result.append(MultipartPart(name: name, filename: filename, body: Array(bodyBytes)))
            }
            _ = crlf
        }
        return result
    }

    private static func extractBoundary(_ contentType: String) -> String? {
        for part in contentType.split(separator: ";") {
            let kv = part.trimmingCharacters(in: .whitespaces)
            if kv.lowercased().hasPrefix("boundary=") {
                var b = String(kv.dropFirst("boundary=".count))
                if b.hasPrefix("\"") && b.hasSuffix("\"") {
                    b = String(b.dropFirst().dropLast())
                }
                return b
            }
        }
        return nil
    }

    private static func parseContentDisposition(_ header: String) -> (name: String?, filename: String?) {
        var name: String? = nil
        var filename: String? = nil
        for raw in header.split(separator: ";") {
            let piece = raw.trimmingCharacters(in: .whitespaces)
            if piece.hasPrefix("name=") {
                name = unquote(String(piece.dropFirst("name=".count)))
            } else if piece.hasPrefix("filename=") {
                filename = unquote(String(piece.dropFirst("filename=".count)))
            }
        }
        return (name, filename)
    }

    private static func unquote(_ s: String) -> String {
        var out = s
        if out.hasPrefix("\"") && out.hasSuffix("\"") && out.count >= 2 {
            out = String(out.dropFirst().dropLast())
        }
        return out
    }

    private static func range(of needle: [UInt8], in haystack: [UInt8], from: Int) -> Int? {
        if needle.isEmpty || haystack.count - from < needle.count { return nil }
        var i = from
        while i <= haystack.count - needle.count {
            var match = true
            for j in 0..<needle.count {
                if haystack[i + j] != needle[j] { match = false; break }
            }
            if match { return i }
            i += 1
        }
        return nil
    }
}

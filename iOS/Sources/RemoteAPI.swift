import Foundation
import Security
import LocalAuthentication

enum JSONValue: Codable, Equatable, Hashable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    var object: [String: JSONValue] { if case .object(let v) = self { return v }; return [:] }
    var array: [JSONValue] { if case .array(let v) = self { return v }; return [] }
    var text: String {
        switch self {
        case .string(let v): return v
        case .number(let v): return v.formatted(.number.grouping(.never))
        case .bool(let v): return v ? "On" : "Off"
        case .null: return "Inherited / unset"
        case .array(let v): return "\(v.count) items"
        case .object: return "Options"
        }
    }
    static func mergingChanges(original: JSONValue, edited: JSONValue, latest: JSONValue) -> JSONValue {
        guard original != edited else { return latest }
        guard case .object(let before) = original, case .object(let after) = edited, case .object(var merged) = latest else { return edited }
        for key in Set(before.keys).union(after.keys) where before[key] != after[key] {
            if let value = after[key] {
                merged[key] = mergingChanges(original: before[key] ?? .null, edited: value, latest: merged[key] ?? .null)
            } else { merged.removeValue(forKey: key) }
        }
        return .object(merged)
    }
}

struct Instance: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var address: String
    var username: String = "admin"
    var allowInsecureHTTP = false
}

enum RemoteError: LocalizedError {
    case invalidAddress, insecureAddress, http(Int, String), authentication, unsupportedServer, credentialStorage
    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "Enter a hostname or an http(s) URL, including the server's port (usually 8791)."
        case .insecureAddress: return "Use HTTPS remotely, or explicitly allow unencrypted HTTP for a trusted private network."
        case .http(let status, let message): return "Server returned \(status): \(message.prefix(180))"
        case .authentication: return "Sign-in failed. Check your WebUI username and password."
        case .unsupportedServer: return "Update this Controllarr server to a release with Remote Protocol 1 support."
        case .credentialStorage: return "iOS could not store the password securely. Unlock this device and try again."
        }
    }
}

enum ServerAddress {
    static func normalize(_ input: String, allowHTTP: Bool) throws -> URL {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = text.contains("://") ? text : "http://" + text
        guard let components = URLComponents(string: raw),
              let host = components.host, !host.isEmpty,
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port == nil || (1...65535).contains(components.port!),
              let url = components.url else { throw RemoteError.invalidAddress }
        if components.scheme?.lowercased() == "http" && !allowHTTP { throw RemoteError.insecureAddress }
        return url
    }
    static func endpoint(_ base: URL, path: String, query: [String: String] = [:]) -> URL {
        var c = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        c.percentEncodedPath = "/" + (c.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        c.queryItems = query.isEmpty ? nil : query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return c.url!
    }
}

enum CredentialStore {
    private static func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.controllarr.remote",
         kSecAttrAccount as String: id.uuidString]
    }
    static func save(_ password: String, for id: UUID) throws {
        let q = query(id)
        let attributes: [String: Any] = [kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(q as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let result = SecItemAdd(q.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard result == errSecSuccess else { throw RemoteError.credentialStorage }
        } else if status != errSecSuccess { throw RemoteError.credentialStorage }
    }
    static func load(_ id: UUID) -> String? {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        q[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func delete(_ id: UUID) { SecItemDelete(query(id) as CFDictionary) }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

actor RemoteClient {
    let instance: Instance
    private let base: URL
    private let session: URLSession
    private var cookie: String?
    private var password: String

    init(instance: Instance, password: String) throws {
        self.instance = instance
        self.password = password
        base = try ServerAddress.normalize(instance.address, allowHTTP: instance.allowInsecureHTTP)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }

    static func form(_ values: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return Data(values.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
    }

    private func login() async throws {
        var request = URLRequest(url: ServerAddress.endpoint(base, path: "api/v2/auth/login"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(["username": instance.username, "password": password])
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              let header = response.value(forHTTPHeaderField: "Set-Cookie"),
              let sid = header.split(separator: ";").first, sid.hasPrefix("SID="), sid.count > 4,
              String(decoding: data, as: UTF8.self).contains("Ok") else { throw RemoteError.authentication }
        cookie = String(sid)
    }

    func request(_ path: String, method: String = "GET", query: [String: String] = [:], body: Data? = nil,
                 contentType: String = "application/json") async throws -> Data {
        if cookie == nil { try await login() }
        for attempt in 0...1 {
            var request = URLRequest(url: ServerAddress.endpoint(base, path: path, query: query))
            request.httpMethod = method
            request.httpBody = body
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
            if body != nil { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
            let (data, raw) = try await session.data(for: request)
            guard let response = raw as? HTTPURLResponse else { throw RemoteError.http(0, "Invalid response") }
            if [401, 403].contains(response.statusCode), attempt == 0 { cookie = nil; try await login(); continue }
            guard (200...299).contains(response.statusCode) else { throw RemoteError.http(response.statusCode, String(decoding: data, as: UTF8.self)) }
            return data
        }
        throw RemoteError.authentication
    }
    func json(_ path: String, query: [String: String] = [:]) async throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: await request(path, query: query))
    }
    func post(_ path: String, value: JSONValue) async throws {
        _ = try await request(path, method: "POST", body: JSONEncoder().encode(value))
    }
    func action(_ path: String, values: [String: String]) async throws {
        _ = try await request(path, method: "POST", body: Self.form(values), contentType: "application/x-www-form-urlencoded")
    }
    func close() { session.invalidateAndCancel(); cookie = nil; password = "" }
}

struct RemoteTorrent: Decodable, Identifiable, Sendable {
    var id: String { hash }
    let hash: String
    let name: String
    let category: String
    let progress: Double
    let size: Int64
    let dlspeed: Int64
    let upspeed: Int64
    let state: String
    let save_path: String
    let content_path: String
    let ratio: Double
}
struct TorrentPage: Decodable, Sendable {
    let total: Int
    let offset: Int
    let items: [RemoteTorrent]
}
struct RemoteEvent: Codable, Identifiable, Sendable {
    let id: Int
    let kind: String
    let title: String
    let message: String
    let hash: String?
    let timestamp: Double
}
struct EventPage: Decodable, Sendable {
    let epoch: String
    let cursor: Int
    let reset: Bool
    let events: [RemoteEvent]
}

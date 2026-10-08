import XCTest
#if canImport(ControllarrRemote)
@testable import ControllarrRemote
#else
@testable import ControllarrRemoteProtocol
#endif

final class RemoteTests: XCTestCase {
    func testAddressSafety() throws {
        XCTAssertThrowsError(try ServerAddress.normalize("http://example.com:8791", allowHTTP: false))
        XCTAssertThrowsError(try ServerAddress.normalize("HTTP://example.com:8791", allowHTTP: false))
        XCTAssertThrowsError(try ServerAddress.normalize("https://user:password@example.com", allowHTTP: false))
        XCTAssertThrowsError(try ServerAddress.normalize("https://example.com?password=test", allowHTTP: false))
        XCTAssertThrowsError(try ServerAddress.normalize("ftp://example.com", allowHTTP: true))
        XCTAssertEqual(try ServerAddress.normalize("plexbox.local:8791", allowHTTP: true).host, "plexbox.local")
        XCTAssertEqual(try ServerAddress.normalize("https://[fd00::1]:8791", allowHTTP: false).port, 8791)
    }
    func testProxyPathAndEscaping() throws {
        let base = try XCTUnwrap(URL(string: "https://example.com/controllarr"))
        let url = ServerAddress.endpoint(base, path: "api/controllarr/categories/TV%20Shows", query: ["search": "a&b + c"])
        XCTAssertEqual(url.path, "/controllarr/api/controllarr/categories/TV Shows")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "a&b + c")
        let form = String(decoding: RemoteClient.form(["password": "a&b+c= d"]), as: UTF8.self)
        XCTAssertEqual(form, "password=a%26b%2Bc%3D%20d")
    }
    func testJSONRoundTripPreservesUnknownSettings() throws {
        let data = Data(#"{"vpn_enabled":true,"preferred_listen_port":53127,"future":{"keys":["a",null,3.5]},"password":"secret"}"#.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)), value)
    }
    func testTorrentContract() throws {
        let data = Data(#"{"total":10000,"offset":100,"items":[{"hash":"abc","name":"Example","category":"TV","progress":0.5,"size":1024,"dlspeed":100,"upspeed":0,"state":"metaDL","save_path":"/tmp","content_path":"","ratio":0}]}"#.utf8)
        let page = try JSONDecoder().decode(TorrentPage.self, from: data)
        XCTAssertEqual(page.total, 10000)
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items.first?.id, "abc")
    }
    func testSettingsMergePreservesConcurrentNestedChanges() {
        let original: JSONValue = .object(["limits": .object(["download": .number(1), "upload": .number(2)])])
        let edited: JSONValue = .object(["limits": .object(["download": .number(10), "upload": .number(2)])])
        let latest: JSONValue = .object(["limits": .object(["download": .number(1), "upload": .number(20), "new": .bool(true)]), "future": .string("keep")])
        let merged = JSONValue.mergingChanges(original: original, edited: edited, latest: latest)
        XCTAssertEqual(merged.object["limits"]?.object["upload"], .number(20))
        XCTAssertEqual(merged.object["limits"]?.object["download"], .number(10))
        XCTAssertEqual(merged.object["limits"]?.object["new"], .bool(true))
        XCTAssertEqual(merged.object["future"], .string("keep"))
    }
    func testEventContractAndReset() throws {
        let page = try JSONDecoder().decode(EventPage.self, from: Data(#"{"epoch":"one","cursor":0,"reset":true,"events":[]}"#.utf8))
        XCTAssertTrue(page.reset)
        XCTAssertEqual(page.events.count, 0)
    }
}

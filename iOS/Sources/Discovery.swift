import Foundation
import Observation

@MainActor @Observable
final class Discovery: NSObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    var instances: [Instance] = []
    var message = "Searching your local network..."
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    func start() {
        browser.delegate = self
        browser.searchForServices(ofType: "_controllarr._tcp.", inDomain: "local.")
    }
    func stop() { browser.stop(); services.forEach { $0.stop() }; services = [] }
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service); service.delegate = self; service.resolve(withTimeout: 8)
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeAll { $0 == service }
        instances.removeAll { $0.name == service.name }
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = sender.hostName, sender.port > 0 else { return }
        let address = "http://\(host):\(sender.port)"
        instances.removeAll { $0.address == address }
        instances.append(Instance(name: sender.name, address: address, allowInsecureHTTP: true))
        message = "Select a server to sign in. Discovery never bypasses authentication."
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        message = "Discovery is unavailable. Allow Local Network access in system Settings, or enter a hostname manually."
    }
}

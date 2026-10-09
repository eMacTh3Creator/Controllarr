import Foundation
import Observation

enum RemoteDestination: String, CaseIterable, Identifiable {
    case overview, torrents, categories, activity, vpn, health, postprocessor, seeding, recovery, log, settings, alerts, instances
    var id: Self { self }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .torrents: "Torrents"
        case .categories: "Categories"
        case .activity: "Activity"
        case .vpn: "VPN & Network"
        case .health: "Health"
        case .postprocessor: "Post-Processing"
        case .seeding: "Seeding Policy"
        case .recovery: "Recovery"
        case .log: "Server Log"
        case .settings: "Settings"
        case .alerts: "Notifications"
        case .instances: "Instances"
        }
    }
    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .torrents: "arrow.down.circle"
        case .categories: "folder"
        case .activity: "bell.badge"
        case .vpn: "network"
        case .health: "heart.text.clipboard"
        case .postprocessor: "shippingbox"
        case .seeding: "arrow.up.forward.circle"
        case .recovery: "wrench.and.screwdriver"
        case .log: "text.alignleft"
        case .settings: "slider.horizontal.3"
        case .alerts: "bell"
        case .instances: "server.rack"
        }
    }
    var tab: Self {
        switch self {
        case .torrents, .categories, .settings: self
        case .alerts, .instances: .settings
        default: .overview
        }
    }
}

enum RemoteLayout {
    static func usesSidebar(width: Double, height: Double) -> Bool { width >= 760 && height >= 480 }
    static func usesTable(width: Double, accessibilityText: Bool) -> Bool { width >= 680 && !accessibilityText }
    static func dashboardColumns(width: Double, accessibilityText: Bool) -> Int {
        if accessibilityText || width < 360 { return 1 }
        return width >= 1000 ? 4 : 2
    }
}

struct RemotePageRequest: Equatable, Sendable {
    static let limit = 100
    let offset: Int
    let search: String
    let category: String?
    var query: [String: String] {
        var values = ["offset": String(offset), "limit": String(Self.limit), "search": search]
        if let category { values["category"] = category }
        return values
    }
    static func lastOffset(total: Int) -> Int { max(0, ((max(1, total) - 1) / limit) * limit) }
}

@MainActor @Observable
final class RemoteWorkspace {
    var destination: RemoteDestination = .overview
    var selectedHashes: Set<String> = []
    var selecting = false
    var showInspector = false
    var showAdd = false
    var showInstances = false
    var confirmDelete = false
    var sortOrder = [KeyPathComparator(\RemoteTorrent.name)]
    func inspect(_ hash: String) { selectedHashes = [hash]; showInspector = true }
    func reconcile(with torrents: [RemoteTorrent]) {
        selectedHashes.formIntersection(Set(torrents.map(\.hash)))
    }
}

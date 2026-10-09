#if DEBUG
import Foundation

extension RemoteModel {
    // A disconnected fixture lets layout checks run without contacting a real server.
    func loadLayoutPreview() {
        let instance = Instance(name: "Layout Preview", address: "preview.invalid")
        instances = [instance]; selectedID = instance.id; platform = "Windows"
        total = 2400
        categories = ["TV", "Movies", "Linux"].map {
            .object(["name": .string($0), "save_path": .string("D:/Downloads/" + $0), "create_torrent_subfolder": .bool(true)])
        }
        torrents = (1...100).map(Self.previewTorrent)
        session = .object(["torrent_count": .number(2400), "download_rate": .number(27_262_976), "upload_rate": .number(2_097_152), "listen_port": .number(53127)])
        events = [RemoteEvent(id: 1, kind: "completed", title: "Torrent Completed", message: "Linux Desktop Installation Image is ready.", hash: nil, timestamp: Date().timeIntervalSince1970 - 90),
                  RemoteEvent(id: 2, kind: "port_changed", title: "Listen Port Changed", message: "Preferred port 53127 is active.", hash: nil, timestamp: Date().timeIntervalSince1970 - 600)]
        lastUpdated = Date()
    }
    private static func previewTorrent(_ index: Int) -> RemoteTorrent {
        let name = index % 3 == 0 ? "Linux Desktop Installation Image \(index)" : "Example Transfer \(index)"
        let category = ["TV", "Movies", "Linux"][index % 3]
        let download: Int64 = index % 4 == 0 ? 0 : Int64(index) * 102_400
        let state = index % 11 == 0 ? "error" : (index % 10 == 0 ? "seeding" : "downloading")
        return RemoteTorrent(hash: String(format: "%040d", index), name: name, category: category,
                             progress: Double(index % 11) / 10, size: 4_294_967_296, dlspeed: download,
                             upspeed: Int64(index) * 1024, state: state, save_path: "D:/Downloads",
                             content_path: "D:/Downloads/" + name, ratio: Double(index) / 10)
    }
}
#endif

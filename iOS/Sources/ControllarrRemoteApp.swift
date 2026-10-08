import SwiftUI

@main
struct ControllarrRemoteApp: App {
    @State private var model = RemoteModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RemoteRoot().environment(model).tint(Color(red: 0.08, green: 0.62, blue: 0.52))
                .onChange(of: phase, initial: true) { _, phase in model.setActive(phase == .active) }
        }
        .backgroundTask(.appRefresh("com.controllarr.remote.refresh")) {
            let background = await RemoteModel()
            await background.backgroundRefresh()
        }
    }
}

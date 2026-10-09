import SwiftUI

@main
struct ControllarrRemoteApp: App {
    @State private var model = RemoteModel()
    @State private var workspace = RemoteWorkspace()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RemoteRoot().environment(model).environment(workspace).tint(Color(red: 0.08, green: 0.62, blue: 0.52))
                .onChange(of: phase, initial: true) { _, phase in model.setActive(phase == .active) }
                #if os(macOS)
                .frame(minWidth: 640, minHeight: 480)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .commands { RemoteCommands(model: model, workspace: workspace) }
        #else
        .backgroundTask(.appRefresh("com.controllarr.remote.refresh")) {
            let background = await RemoteModel()
            await background.backgroundRefresh()
        }
        #endif
    }
}

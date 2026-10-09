import SwiftUI
#if os(macOS)
import AppKit
#endif

enum RemoteColors {
    static var grouped: Color {
        #if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }
    static var card: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
}

extension View {
    @ViewBuilder func remotePlainInput() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }
    @ViewBuilder func remoteURLInput() -> some View {
        #if os(iOS)
        self.keyboardType(.URL).remotePlainInput()
        #else
        self.remotePlainInput()
        #endif
    }
    @ViewBuilder func remoteNumericInput() -> some View {
        #if os(iOS)
        self.keyboardType(.numbersAndPunctuation)
        #else
        self
        #endif
    }
    @ViewBuilder func remoteSheet() -> some View {
        #if os(macOS)
        self.frame(minWidth: 480, idealWidth: 620, minHeight: 440, idealHeight: 660)
        #else
        self.presentationDragIndicator(.visible)
        #endif
    }
    @ViewBuilder func remoteDeleteCommand(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
        self.onDeleteCommand(perform: action)
        #else
        self
        #endif
    }
}

#if os(macOS)
struct RemoteCommands: Commands {
    let model: RemoteModel
    let workspace: RemoteWorkspace
    var body: some Commands {
        SidebarCommands()
        CommandGroup(after: .newItem) {
            Button("Add Torrents...") { workspace.showAdd = true }
                .keyboardShortcut("n").disabled(model.client == nil)
        }
        CommandMenu("Server") {
            Button("Refresh") { Task { await model.refresh() } }.keyboardShortcut("r")
                .disabled(model.client == nil)
            Button("Reconnect") { Task { await model.connect() } }.disabled(model.selected == nil)
            Divider()
            Button("Manage Instances...") { workspace.showInstances = true }.keyboardShortcut(",")
        }
        CommandMenu("Transfers") {
            Button("Pause Selected") { Task { await model.action("pause", hashes: workspace.selectedHashes) } }
                .disabled(workspace.selectedHashes.isEmpty || model.busy)
            Button("Resume Selected") { Task { await model.action("resume", hashes: workspace.selectedHashes) } }
                .disabled(workspace.selectedHashes.isEmpty || model.busy)
            Divider()
            Button("Remove Selected...") { workspace.destination = .torrents; workspace.confirmDelete = true }
                .disabled(workspace.selectedHashes.isEmpty || model.busy)
        }
    }
}
#endif

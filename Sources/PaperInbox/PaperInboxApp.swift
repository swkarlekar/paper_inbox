import SwiftUI

@main
struct PaperInboxApp: App {
    @StateObject private var viewModel = LibraryViewModel.makeDefault()

    var body: some Scene {
        MenuBarExtra("PaperInbox", systemImage: "tray.and.arrow.down") {
            MenuBarView()
                .environmentObject(viewModel)
        }

        Window("PaperInbox Library", id: "library") {
            LibraryWindow()
                .environmentObject(viewModel)
        }
        .defaultSize(width: 1180, height: 760)

        Settings {
            SettingsView()
                .environmentObject(viewModel)
        }
    }
}

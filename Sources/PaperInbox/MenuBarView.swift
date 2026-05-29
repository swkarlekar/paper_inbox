import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var viewModel: LibraryViewModel

    var body: some View {
        Button("Quick Add Paper...") {
            openLibrary()
            viewModel.isShowingAddPaper = true
        }

        Button("Add Clipboard URLs") {
            openLibrary()
            viewModel.addClipboardURL()
        }

        Divider()

        Button("Open Library") {
            viewModel.showToStudyLanding()
            openLibrary()
        }

        Button("Import ChatGPT Output from Clipboard") {
            openLibrary()
            viewModel.importFromClipboard()
        }

        Button("Import ChatGPT Export...") {
            openLibrary()
            viewModel.alertMessage = AlertMessage(
                title: "Not Implemented Yet",
                message: "ChatGPT export ZIP import is planned for Phase 3."
            )
        }

        Divider()

        Button("Settings") {
            if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            }
        }

        Button("Quit") {
            NSApp.terminate(nil)
        }
    }

    private func openLibrary() {
        openWindow(id: "library")
        bringLibraryToFront()

        DispatchQueue.main.async {
            bringLibraryToFront()
        }
    }

    private func bringLibraryToFront() {
        NSApp.activate(ignoringOtherApps: true)

        let libraryWindow = NSApp.windows.first { window in
            window.title == "PaperInbox Library" || window.title == "PaperInbox"
        }
        libraryWindow?.makeKeyAndOrderFront(nil)
    }
}

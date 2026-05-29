import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @State private var preferDesktopApp = true
    @State private var automaticallyPastePrompt = false
    @State private var experimentalPDFAttach = false

    var body: some View {
        TabView {
            Form {
                TextField("Storage Location", text: .constant(viewModel.storagePath))
                    .textSelection(.enabled)
                Toggle("Show hidden/read papers in collections by default", isOn: $viewModel.includeReadArchivedInCollections)
            }
            .padding(20)
            .tabItem { Text("General") }

            Form {
                Toggle("Prefer ChatGPT desktop app", isOn: $preferDesktopApp)
                Toggle("Automatically paste prompt into ChatGPT", isOn: $automaticallyPastePrompt)
                    .disabled(true)
                Toggle("Experimental: automatically attach PDF", isOn: $experimentalPDFAttach)
                    .disabled(true)
                Text("Automatic paste and PDF attachment are reserved for a later pass. Prompts are copied and ChatGPT is opened when possible.")
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .tabItem { Text("ChatGPT") }

            Form {
                Text("Prompt templates are hardcoded to the implementation spec in this build.")
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .tabItem { Text("Prompts") }

            Form {
                Text("Clipboard import looks for PaperInbox summary and study guide wrappers.")
                    .foregroundStyle(.secondary)
                Text("ChatGPT export ZIP import is planned for Phase 3.")
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .tabItem { Text("Imports") }
        }
        .frame(width: 560, height: 360)
    }
}

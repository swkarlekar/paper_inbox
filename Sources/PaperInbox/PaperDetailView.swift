import PaperInboxCore
import SwiftUI

struct PaperDetailView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    let paper: Paper
    @State private var editablePaper: Paper
    @State private var isConfirmingDelete = false
    @State private var isEditingMetadata = false

    init(paper: Paper) {
        self.paper = paper
        _editablePaper = State(initialValue: paper)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                metadata
                collections
                sourceActions
                chatGPTActions
                artifactSection(title: "Summary", type: .summary)
                artifactSection(title: "Study Guide", type: .studyGuide)
                artifactSection(title: "Chat Transcript", type: .chatTranscript)
                artifactSection(title: "Notes", type: .notes)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: paper) { newValue in
            editablePaper = newValue
            isEditingMetadata = false
        }
        .confirmationDialog(
            "Delete this paper?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Paper", role: .destructive) {
                viewModel.deletePaper(paper)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the paper from PaperInbox and deletes its local folder and imported artifacts.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: $editablePaper.title)
                .font(.title2.weight(.semibold))
                .textFieldStyle(.plain)
                .onSubmit { viewModel.updatePaper(editablePaper) }

            HStack {
                StatusBadge(status: paper.status)

                Picker("Status", selection: Binding(
                    get: { paper.status },
                    set: { viewModel.updateStatus(for: paper, status: $0) }
                )) {
                    ForEach(PaperStatus.allCases) { status in
                        Text(status.displayName).tag(status)
                    }
                }
                .labelsHidden()
                .frame(width: 190)

                Spacer()
            }
        }
    }

    private var metadata: some View {
        DetailGroup(title: "Metadata") {
            if isEditingMetadata {
                metadataEditor
            } else {
                metadataDisplay
            }
        }
    }

    private var metadataDisplay: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
                metadataDisplayRow("Authors", value: paper.authors)
                metadataDisplayRow("Venue", value: paper.venue)
                metadataDisplayRow("Year", value: paper.year.map(String.init))
            }

            if let abstract = cleanedDisplayValue(paper.abstract) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Abstract")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(abstract)
                        .font(.callout)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                }
                .padding(.top, 2)
            }

            HStack {
                Spacer()
                Button {
                    editablePaper = paper
                    isEditingMetadata = true
                } label: {
                    Label("Edit Metadata", systemImage: "pencil")
                }
                .controlSize(.small)
            }
        }
    }

    private var metadataEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                editableField("Authors", text: Binding(
                    get: { editablePaper.authors ?? "" },
                    set: { editablePaper.authors = normalizedOptionalText($0) }
                ))
                editableField("Venue", text: Binding(
                    get: { editablePaper.venue ?? "" },
                    set: { editablePaper.venue = normalizedOptionalText($0) }
                ))
                editableField("Year", text: Binding(
                    get: { editablePaper.year.map(String.init) ?? "" },
                    set: { editablePaper.year = Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                ))
            }

            TextField("Abstract", text: Binding(
                get: { editablePaper.abstract ?? "" },
                set: { editablePaper.abstract = normalizedOptionalText($0) }
            ), axis: .vertical)
            .lineLimit(3...8)

            HStack {
                Spacer()
                Button("Cancel") {
                    editablePaper = paper
                    isEditingMetadata = false
                }
                Button {
                    viewModel.updatePaper(editablePaper)
                    isEditingMetadata = false
                } label: {
                    Label("Save Metadata", systemImage: "checkmark")
                }
            }
        }
    }

    private func metadataDisplayRow(_ label: String, value: String?) -> some View {
        GridRow {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(cleanedDisplayValue(value) ?? "Not set")
                .font(.callout)
                .foregroundStyle(cleanedDisplayValue(value) == nil ? .tertiary : .primary)
                .textSelection(.enabled)
        }
    }

    private func editableField(_ label: String, text: Binding<String>) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func normalizedOptionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func cleanedDisplayValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var collections: some View {
        DetailGroup(title: "Collections") {
            if viewModel.collections.isEmpty {
                Text("No collections yet.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(viewModel.collections) { collection in
                        let isMember = viewModel.isPaper(paper, in: collection)
                        Button {
                            viewModel.toggleCollection(collection, for: paper, isMember: !isMember)
                        } label: {
                            CollectionTagView(
                                collection: collection,
                                allCollections: viewModel.collections,
                                isSelected: isMember,
                                size: .regular,
                                showsCheckmark: true
                            )
                        }
                        .buttonStyle(.plain)
                        .help(isMember ? "Remove from collection" : "Add to collection")
                    }
                }
            }
        }
    }

    private var sourceActions: some View {
        DetailGroup(title: "PDF / URL") {
            HStack {
                if paper.localPDFPath != nil {
                    Button {
                        viewModel.revealPDF(for: paper)
                    } label: {
                        Label("Reveal PDF", systemImage: "magnifyingglass")
                    }
                }

                if paper.sourceURL != nil {
                    Button {
                        viewModel.openSourceURL(for: paper)
                    } label: {
                        Label("Open Source URL", systemImage: "safari")
                    }
                }
            }

            if let path = paper.localPDFPath {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let sourceURL = paper.sourceURL {
                Text(sourceURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var chatGPTActions: some View {
        DetailGroup(title: "Actions") {
            HStack {
                Button {
                    viewModel.launchPrompt(for: paper, mode: .summary)
                } label: {
                    Label("Launch Summary in ChatGPT", systemImage: "paperplane")
                }

                Button {
                    viewModel.launchPrompt(for: paper, mode: .studyGuide)
                } label: {
                    Label("Launch Study Guide in ChatGPT", systemImage: "book.closed")
                }
            }

            HStack {
                Button {
                    viewModel.copyPrompt(for: paper, mode: .summary)
                } label: {
                    Label("Copy Summary Prompt", systemImage: "doc.on.doc")
                }

                Button {
                    viewModel.copyPrompt(for: paper, mode: .studyGuide)
                } label: {
                    Label("Copy Study Guide Prompt", systemImage: "doc.on.doc.fill")
                }
            }

            HStack {
                Button("Mark To Study") {
                    viewModel.updateStatus(for: paper, status: .toStudy)
                }
                Button("Mark Read") {
                    viewModel.updateStatus(for: paper, status: .read)
                }
                Button("Archive") {
                    viewModel.updateStatus(for: paper, status: .archived)
                }
                Button("Restore to Inbox") {
                    viewModel.updateStatus(for: paper, status: .unread)
                }
                Button("Delete Paper", role: .destructive) {
                    isConfirmingDelete = true
                }
            }
        }
    }

    @ViewBuilder
    private func artifactSection(title: String, type: ArtifactType) -> some View {
        let artifacts = viewModel.artifacts(for: paper, type: type)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.headline)

                if [.summary, .studyGuide].contains(type) {
                    ArtifactChatLinkView(
                        paper: paper,
                        type: type,
                        currentURL: viewModel.chatGPTURL(for: paper, type: type)
                    )
                }
            }

            if let artifact = artifacts.first {
                ArtifactRendererView(markdown: artifact.contentMarkdown)
                    .frame(minHeight: 260, idealHeight: 480, maxHeight: 640)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary, lineWidth: 1)
                    }
            } else {
                Text("No \(title.lowercased()) imported yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ArtifactChatLinkView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    let paper: Paper
    let type: ArtifactType
    let currentURL: String
    @State private var urlString: String
    @State private var isEditing: Bool

    init(paper: Paper, type: ArtifactType, currentURL: String) {
        self.paper = paper
        self.type = type
        self.currentURL = currentURL
        _urlString = State(initialValue: currentURL)
        _isEditing = State(initialValue: currentURL.isEmpty)
    }

    var body: some View {
        Group {
            if isEditing {
                HStack(spacing: 6) {
                    TextField("Paste ChatGPT chat link", text: $urlString)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 230, idealWidth: 300, maxWidth: 380)
                        .onSubmit(save)

                    Button {
                        save()
                    } label: {
                        Label("Save ChatGPT Link", systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                    .help("Save ChatGPT link")

                    if !currentURL.isEmpty {
                        Button {
                            urlString = currentURL
                            isEditing = false
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                                .labelStyle(.iconOnly)
                        }
                        .help("Cancel")
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Button {
                        viewModel.openChatGPTURL(currentURL)
                    } label: {
                        Label("ChatGPT chat", systemImage: "bubble.left.and.text.bubble.right")
                    }
                    .buttonStyle(.bordered)
                    .help("Open saved ChatGPT chat")

                    Button {
                        viewModel.copyChatGPTURL(currentURL)
                    } label: {
                        Label("Copy ChatGPT Link", systemImage: "doc.on.doc")
                            .labelStyle(.iconOnly)
                    }
                    .help("Copy ChatGPT link")

                    Button {
                        isEditing = true
                    } label: {
                        Label("Edit ChatGPT Link", systemImage: "pencil")
                            .labelStyle(.iconOnly)
                    }
                    .help("Edit ChatGPT link")
                }
            }
        }
        .controlSize(.small)
        .onChange(of: currentURL) { newValue in
            urlString = newValue
            isEditing = newValue.isEmpty
        }
    }

    private func save() {
        viewModel.updateArtifactChatGPTURL(paper: paper, type: type, urlString: urlString)
        isEditing = urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct DetailGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

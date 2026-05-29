import AppKit
import Combine
import Foundation
import PaperInboxCore
import UniformTypeIdentifiers

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var papers: [Paper] = []
    @Published var collections: [PaperCollection] = []
    @Published var memberships: [PaperCollectionMembership] = []
    @Published var artifactsByPaperID: [String: [Artifact]] = [:]
    @Published var chatLinksByPaperAndType: [String: String] = [:]
    @Published var displayedPapers: [Paper] = []
    @Published var paperListResetID = UUID()
    @Published var selectedPaperIDs: Set<String> = [] {
        didSet {
            guard !isSynchronizingSelection else { return }
            synchronizePrimarySelectionFromSelectedSet(oldValue: oldValue)
        }
    }
    @Published var selectedPaperID: String? {
        didSet {
            guard !isSynchronizingSelection else { return }
            synchronizeSelectedSetFromPrimarySelection()
        }
    }
    @Published var selectedFilter: LibraryFilter? = .toStudy {
        didSet {
            let filterChanged = oldValue != selectedFilter
            refreshDisplayedPapers(selectFirstPaper: filterChanged)
            if filterChanged {
                paperListResetID = UUID()
            }
        }
    }
    @Published var searchText: String = "" {
        didSet { refreshDisplayedPapers() }
    }
    @Published var includeReadArchivedInCollections = false {
        didSet { refreshDisplayedPapers() }
    }
    @Published var isShowingAddPaper = false
    @Published var isShowingNewCollection = false
    @Published var collectionPendingRename: PaperCollection?
    @Published var alertMessage: AlertMessage?

    let store: PaperInboxStore?
    let startupError: Error?
    private var isSynchronizingSelection = false
    private var selectionAnchorPaperID: String?

    static func makeDefault() -> LibraryViewModel {
        do {
            return try LibraryViewModel(store: PaperInboxStore())
        } catch {
            return LibraryViewModel(startupError: error)
        }
    }

    init(store: PaperInboxStore) throws {
        self.store = store
        self.startupError = nil
        try reload()
    }

    init(startupError: Error) {
        self.store = nil
        self.startupError = startupError
        self.alertMessage = AlertMessage(
            title: "Could not open PaperInbox",
            message: startupError.localizedDescription
        )
    }

    var selectedPaper: Paper? {
        guard let selectedPaperID else { return nil }
        return papers.first { $0.id == selectedPaperID }
    }

    var storagePath: String {
        store?.storage.baseURL.path ?? "Unavailable"
    }

    func reload() throws {
        guard let store else { return }
        let snapshot = try store.loadSnapshot()
        papers = snapshot.papers
        collections = snapshot.collections
        memberships = snapshot.memberships
        artifactsByPaperID = Dictionary(grouping: snapshot.artifacts, by: \.paperID)
        chatLinksByPaperAndType = Dictionary(
            snapshot.artifactChatLinks.map {
                (chatLinkKey(paperID: $0.paperID, type: $0.type), $0.chatGPTURL)
            },
            uniquingKeysWith: { first, _ in first }
        )
        refreshDisplayedPapers()
    }

    func reloadAndReportErrors() {
        do {
            try reload()
        } catch {
            present(error)
        }
    }

    func showToStudyLanding() {
        searchText = ""
        selectedFilter = .toStudy
    }

    func showInbox(selecting paperID: String? = nil) {
        searchText = ""
        selectedFilter = .inbox
        if let paperID {
            selectedPaperID = paperID
        }
    }

    func addURL(_ rawURL: String) {
        Task { @MainActor in
            await addURLWithMetadata(rawURL)
        }
    }

    private func addURLWithMetadata(_ rawURL: String) async {
        guard let store else { return }
        do {
            let paper = try await store.createPaperFromURL(
                rawURL,
                allowNetworkMetadataLookup: true
            )
            try reload()
            showInbox(selecting: paper.id)
        } catch {
            present(error)
        }
    }

    func addClipboardURL() {
        guard let value = NSPasteboard.general.string(forType: .string) else {
            alertMessage = AlertMessage(title: "No URL Found", message: "The clipboard does not contain a URL.")
            return
        }

        let urls = ClipboardURLExtractor().paperURLs(from: value)
        guard !urls.isEmpty else {
            alertMessage = AlertMessage(title: "No URL Found", message: "The clipboard does not contain any URLs.")
            return
        }

        Task { @MainActor in
            await addClipboardURLs(urls)
        }
    }

    private func addClipboardURLs(_ urls: [URL]) async {
        guard let store else { return }
        let extractor = ClipboardURLExtractor()
        var knownURLs = Set(
            papers.compactMap(\.sourceURL).flatMap { sourceURL -> [String] in
                var values = [sourceURL]
                if let canonical = extractor.canonicalPaperURLString(for: sourceURL) {
                    values.append(canonical)
                }
                return values
            }
        )

        var addedCount = 0
        var skippedCount = 0
        var failedCount = 0
        var lastAddedPaperID: String?

        for url in urls {
            let canonicalURL = extractor.canonicalPaperURLString(for: url.absoluteString) ?? url.absoluteString
            guard knownURLs.contains(url.absoluteString) == false,
                  knownURLs.contains(canonicalURL) == false else {
                skippedCount += 1
                continue
            }

            do {
                let paper = try await store.createPaperFromURL(
                    canonicalURL,
                    allowNetworkMetadataLookup: true
                )
                knownURLs.insert(url.absoluteString)
                knownURLs.insert(canonicalURL)
                addedCount += 1
                lastAddedPaperID = paper.id
            } catch {
                failedCount += 1
            }
        }

        do {
            try reload()
            if let lastAddedPaperID {
                showInbox(selecting: lastAddedPaperID)
            }
        } catch {
            present(error)
            return
        }

        reportClipboardURLImport(addedCount: addedCount, skippedCount: skippedCount, failedCount: failedCount)
    }

    private func reportClipboardURLImport(addedCount: Int, skippedCount: Int, failedCount: Int) {
        if addedCount > 0 {
            var details = ["Added \(addedCount) paper URL\(addedCount == 1 ? "" : "s") from the clipboard."]
            if skippedCount > 0 {
                details.append("Skipped \(skippedCount) duplicate\(skippedCount == 1 ? "" : "s").")
            }
            if failedCount > 0 {
                details.append("\(failedCount) URL\(failedCount == 1 ? "" : "s") could not be added.")
            }
            alertMessage = AlertMessage(title: "Clipboard URLs Added", message: details.joined(separator: " "))
        } else if skippedCount > 0 && failedCount == 0 {
            alertMessage = AlertMessage(
                title: "No New URLs Added",
                message: "All detected clipboard URLs are already in PaperInbox."
            )
        } else {
            alertMessage = AlertMessage(
                title: "No URLs Added",
                message: "\(failedCount) URL\(failedCount == 1 ? "" : "s") could not be added."
            )
        }
    }

    func choosePDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.addPDF(url)
            }
        }
    }

    func addPDF(_ url: URL) {
        guard let store else { return }
        do {
            let paper = try store.createPaperFromPDF(sourceURL: url)
            try reload()
            showInbox(selecting: paper.id)
        } catch {
            present(error)
        }
    }

    func createCollection(name: String) {
        guard let store else { return }
        do {
            _ = try store.createCollection(name: name)
            try reload()
        } catch {
            present(error)
        }
    }

    func deleteCollection(_ collection: PaperCollection) {
        guard let store else { return }
        do {
            try store.deleteCollection(id: collection.id)
            if selectedFilter == .collection(collection.id) {
                selectedFilter = .inbox
            }
            try reload()
        } catch {
            present(error)
        }
    }

    func renameCollection(_ collection: PaperCollection, name: String) {
        guard let store else { return }
        do {
            try store.renameCollection(id: collection.id, name: name)
            try reload()
        } catch {
            present(error)
        }
    }

    func updateStatus(for paper: Paper, status: PaperStatus) {
        guard let store else { return }
        do {
            try store.updateStatus(paperID: paper.id, status: status)
            try reload()
            selectedPaperID = paper.id
        } catch {
            present(error)
        }
    }

    func deletePaper(_ paper: Paper) {
        guard let store else { return }
        do {
            try store.deletePaper(id: paper.id)
            try reload()
            if selectedPaperID == paper.id {
                selectedPaperID = displayedPapers.first?.id
            }
        } catch {
            present(error)
        }
    }

    func selectPaper(_ paper: Paper, modifierFlags: NSEvent.ModifierFlags = []) {
        if modifierFlags.contains(.shift) {
            selectRange(to: paper, extendingCurrentSelection: modifierFlags.contains(.command))
        } else if modifierFlags.contains(.command) {
            togglePaperSelection(paper)
        } else {
            setSelection(paperIDs: [paper.id], primaryPaperID: paper.id)
            selectionAnchorPaperID = paper.id
        }
    }

    func updatePaper(_ paper: Paper) {
        guard let store else { return }
        do {
            try store.updatePaper(paper)
            try reload()
            selectedPaperID = paper.id
        } catch {
            present(error)
        }
    }

    func toggleCollection(_ collection: PaperCollection, for paper: Paper, isMember: Bool) {
        guard let store else { return }
        do {
            try store.setCollectionMembership(
                paperID: paper.id,
                collectionID: collection.id,
                isMember: isMember
            )
            try reload()
            selectedPaperID = paper.id
        } catch {
            present(error)
        }
    }

    func dragProvider(for paper: Paper) -> NSItemProvider {
        PaperDragPayload.provider(for: paperIDsForDrag(startingWith: paper))
    }

    func addDroppedPapers(_ providers: [NSItemProvider], to collection: PaperCollection) -> Bool {
        var acceptedDrop = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(PaperDragPayload.type.identifier) {
                acceptedDrop = true
                provider.loadDataRepresentation(forTypeIdentifier: PaperDragPayload.type.identifier) { [weak self] data, _ in
                    guard let data else { return }
                    let paperIDs = PaperDragPayload.paperIDs(from: data)
                    Task { @MainActor [weak self] in
                        self?.addPaperIDs(paperIDs, to: collection)
                    }
                }
                continue
            }

            if provider.canLoadObject(ofClass: NSString.self) {
                acceptedDrop = true
                _ = provider.loadObject(ofClass: NSString.self) { [weak self] value, _ in
                    guard let string = value as? String else { return }
                    let paperIDs = PaperDragPayload.paperIDs(fromText: string)
                    Task { @MainActor [weak self] in
                        self?.addPaperIDs(paperIDs, to: collection)
                    }
                }
            }
        }

        return acceptedDrop
    }

    func addDroppedPapers(_ providers: [NSItemProvider], toStatus status: PaperStatus) -> Bool {
        var acceptedDrop = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(PaperDragPayload.type.identifier) {
                acceptedDrop = true
                provider.loadDataRepresentation(forTypeIdentifier: PaperDragPayload.type.identifier) { [weak self] data, _ in
                    guard let data else { return }
                    let paperIDs = PaperDragPayload.paperIDs(from: data)
                    Task { @MainActor [weak self] in
                        self?.updatePaperIDs(paperIDs, status: status)
                    }
                }
                continue
            }

            if provider.canLoadObject(ofClass: NSString.self) {
                acceptedDrop = true
                _ = provider.loadObject(ofClass: NSString.self) { [weak self] value, _ in
                    guard let string = value as? String else { return }
                    let paperIDs = PaperDragPayload.paperIDs(fromText: string)
                    Task { @MainActor [weak self] in
                        self?.updatePaperIDs(paperIDs, status: status)
                    }
                }
            }
        }

        return acceptedDrop
    }

    func isPaper(_ paper: Paper, in collection: PaperCollection) -> Bool {
        memberships.contains {
            $0.paperID == paper.id && $0.collectionID == collection.id
        }
    }

    func collections(for paper: Paper) -> [PaperCollection] {
        let ids = Set(memberships.filter { $0.paperID == paper.id }.map(\.collectionID))
        return collections.filter { ids.contains($0.id) }
    }

    func collectionNames(for paper: Paper) -> [String] {
        collections(for: paper).map(\.name)
    }

    func paperCount(in collection: PaperCollection) -> Int {
        Set(memberships.filter { $0.collectionID == collection.id }.map(\.paperID)).count
    }

    func artifacts(for paper: Paper, type: ArtifactType) -> [Artifact] {
        artifactsByPaperID[paper.id, default: []].filter { $0.type == type }
    }

    func hasArtifact(_ type: ArtifactType, for paper: Paper) -> Bool {
        artifacts(for: paper, type: type).isEmpty == false
    }

    func chatGPTURL(for paper: Paper, type: ArtifactType) -> String {
        chatLinksByPaperAndType[chatLinkKey(paperID: paper.id, type: type)] ?? ""
    }

    func revealPDF(for paper: Paper) {
        guard let path = paper.localPDFPath else {
            alertMessage = AlertMessage(title: "No PDF", message: "This paper does not have a stored local PDF.")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openSourceURL(for paper: Paper) {
        guard let sourceURL = paper.sourceURL, let url = URL(string: sourceURL) else {
            alertMessage = AlertMessage(title: "No Source URL", message: "This paper does not have a source URL.")
            return
        }
        NSWorkspace.shared.open(url)
    }

    func updateArtifactChatGPTURL(paper: Paper, type: ArtifactType, urlString: String) {
        guard let store else { return }
        do {
            try store.updateArtifactChatGPTURL(
                paperID: paper.id,
                type: type,
                chatGPTURL: urlString
            )
            try reload()
            selectedPaperID = paper.id
        } catch {
            present(error)
        }
    }

    func openChatGPTURL(_ urlString: String?) {
        guard let urlString,
              let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            alertMessage = AlertMessage(title: "No ChatGPT Link", message: "Paste a ChatGPT chat link first.")
            return
        }
        NSWorkspace.shared.open(url)
    }

    func copyChatGPTURL(_ urlString: String?) {
        guard let urlString,
              !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMessage = AlertMessage(title: "No ChatGPT Link", message: "Paste a ChatGPT chat link first.")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
    }

    func copyPrompt(for paper: Paper, mode: LaunchMode) {
        let prompt = PromptBuilder().buildPrompt(paper: paper, mode: mode)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        alertMessage = AlertMessage(title: "Prompt Copied", message: "Paste it into ChatGPT when ready.")
    }

    func launchPrompt(for paper: Paper, mode: LaunchMode) {
        let prompt = PromptBuilder().buildPrompt(paper: paper, mode: mode)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)

        do {
            try store?.recordLaunch(paperID: paper.id)
            try reload()
            selectedPaperID = paper.id
        } catch {
            present(error)
            return
        }

        if openChatGPT() {
            alertMessage = AlertMessage(
                title: "Prompt Copied",
                message: "ChatGPT was opened or refocused. Paste the prompt with Command-V if it was not pasted automatically."
            )
        } else {
            alertMessage = AlertMessage(
                title: "Prompt Copied",
                message: "PaperInbox could not open ChatGPT. Please open ChatGPT manually and paste the prompt."
            )
        }
    }

    func importFromClipboard() {
        guard let store else { return }
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            alertMessage = AlertMessage(
                title: "No Clipboard Text",
                message: "The clipboard does not contain text to import."
            )
            return
        }

        do {
            let imported = try ClipboardImportParser().parse(text)
            guard !imported.isEmpty else {
                alertMessage = AlertMessage(
                    title: "No Wrappers Found",
                    message: "No PaperInbox summary or study guide wrappers were found."
                )
                return
            }

            var count = 0
            for item in imported {
                _ = try store.saveArtifact(
                    paperID: item.paperID,
                    type: item.type,
                    contentMarkdown: item.contentMarkdown,
                    source: .clipboard
                )
                count += 1
            }

            try reload()
            alertMessage = AlertMessage(
                title: "Import Complete",
                message: "Imported \(count) artifact\(count == 1 ? "" : "s") from the clipboard."
            )
        } catch {
            present(error)
        }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                    guard let url = Self.url(fromDroppedItem: item) else { return }
                    Task { @MainActor [weak self] in
                        if url.pathExtension.lowercased() == "pdf" {
                            self?.addPDF(url)
                        } else {
                            self?.addURL(url.absoluteString)
                        }
                    }
                }
                return true
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                    guard let url = Self.url(fromDroppedItem: item) else { return }
                    Task { @MainActor [weak self] in self?.addURL(url.absoluteString) }
                }
                return true
            }

            if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { [weak self] value, _ in
                    guard let string = value as? String else { return }
                    Task { @MainActor [weak self] in self?.addURL(string) }
                }
                return true
            }
        }

        return false
    }

    private func refreshDisplayedPapers(selectFirstPaper: Bool = false) {
        do {
            let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let source = try searchSource(for: trimmedSearch)

            if !trimmedSearch.isEmpty {
                displayedPapers = source
            } else {
                displayedPapers = filter(source, by: selectedFilter ?? .inbox)
            }

            if selectFirstPaper {
                selectedPaperID = displayedPapers.first?.id
            } else if let selectedPaperID,
               displayedPapers.contains(where: { $0.id == selectedPaperID }) == false,
               searchText.isEmpty {
                self.selectedPaperID = displayedPapers.first?.id
            } else if selectedPaperID == nil {
                selectedPaperID = displayedPapers.first?.id
            } else {
                trimSelectionToDisplayedPapers()
            }
        } catch {
            present(error)
        }
    }

    private func searchSource(for query: String) throws -> [Paper] {
        guard let store, !query.isEmpty else { return papers }
        return try store.searchPapers(query: query)
    }

    private func filter(_ papers: [Paper], by filter: LibraryFilter) -> [Paper] {
        switch filter {
        case .inbox:
            return papers.filter { $0.status == .unread && !$0.isHidden }
        case .toStudy:
            return papers.filter { $0.status == .toStudy }
        case .read:
            return papers.filter { $0.status == .read }
        case .archived:
            return papers.filter { $0.status == .archived }
        case .all:
            return papers
        case .collection(let collectionID):
            let paperIDs = Set(memberships.filter { $0.collectionID == collectionID }.map(\.paperID))
            return papers.filter { paper in
                paperIDs.contains(paper.id) && (includeReadArchivedInCollections || !paper.isHidden)
            }
        }
    }

    private func addPaperIDs(_ paperIDs: [String], to collection: PaperCollection) {
        guard let store else { return }

        let knownPaperIDs = Set(papers.map(\.id))
        let uniquePaperIDs = Set(paperIDs).filter { knownPaperIDs.contains($0) }
        guard !uniquePaperIDs.isEmpty else { return }

        let previousSelectedPaperIDs = selectedPaperIDs
        let previousPrimaryPaperID = selectedPaperID

        do {
            for paperID in uniquePaperIDs {
                try store.setCollectionMembership(
                    paperID: paperID,
                    collectionID: collection.id,
                    isMember: true
                )
            }
            try reload()
            restoreSelection(paperIDs: previousSelectedPaperIDs, primaryPaperID: previousPrimaryPaperID)
        } catch {
            present(error)
        }
    }

    private func updatePaperIDs(_ paperIDs: [String], status: PaperStatus) {
        guard let store else { return }

        let knownPaperIDs = Set(papers.map(\.id))
        let uniquePaperIDs = Set(paperIDs).filter { knownPaperIDs.contains($0) }
        guard !uniquePaperIDs.isEmpty else { return }

        do {
            for paperID in uniquePaperIDs {
                try store.updateStatus(paperID: paperID, status: status)
            }
            try reload()
        } catch {
            present(error)
        }
    }

    private func paperIDsForDrag(startingWith paper: Paper) -> [String] {
        guard selectedPaperIDs.contains(paper.id) else {
            return [paper.id]
        }

        let visibleSelectedPaperIDs = displayedPapers
            .map(\.id)
            .filter { selectedPaperIDs.contains($0) }
        return visibleSelectedPaperIDs.isEmpty ? [paper.id] : visibleSelectedPaperIDs
    }

    private func synchronizePrimarySelectionFromSelectedSet(oldValue: Set<String>) {
        isSynchronizingSelection = true
        defer { isSynchronizingSelection = false }

        if selectedPaperIDs.isEmpty {
            selectedPaperID = nil
            selectionAnchorPaperID = nil
            return
        }

        let newlySelectedPaperIDs = selectedPaperIDs.subtracting(oldValue)
        if let newlySelectedPaperID = displayedPapers
            .map(\.id)
            .first(where: { newlySelectedPaperIDs.contains($0) }) {
            selectedPaperID = newlySelectedPaperID
            selectionAnchorPaperID = newlySelectedPaperID
            return
        }

        if let selectedPaperID, selectedPaperIDs.contains(selectedPaperID) {
            return
        }

        selectedPaperID = displayedPapers
            .map(\.id)
            .first(where: { selectedPaperIDs.contains($0) })
            ?? selectedPaperIDs.first
        selectionAnchorPaperID = selectedPaperID
    }

    private func synchronizeSelectedSetFromPrimarySelection() {
        isSynchronizingSelection = true
        defer { isSynchronizingSelection = false }

        if let selectedPaperID {
            selectedPaperIDs = [selectedPaperID]
            selectionAnchorPaperID = selectedPaperID
        } else {
            selectedPaperIDs = []
            selectionAnchorPaperID = nil
        }
    }

    private func trimSelectionToDisplayedPapers() {
        let displayedPaperIDs = Set(displayedPapers.map(\.id))
        let visibleSelection = selectedPaperIDs.intersection(displayedPaperIDs)

        if visibleSelection != selectedPaperIDs {
            selectedPaperIDs = visibleSelection
        }
    }

    private func restoreSelection(paperIDs: Set<String>, primaryPaperID: String?) {
        let knownPaperIDs = Set(papers.map(\.id))
        let validPaperIDs = paperIDs.intersection(knownPaperIDs)
        let validPrimaryPaperID: String?
        if let primaryPaperID, validPaperIDs.contains(primaryPaperID) {
            validPrimaryPaperID = primaryPaperID
        } else {
            validPrimaryPaperID = displayedPapers
                .map(\.id)
                .first(where: { validPaperIDs.contains($0) })
                ?? validPaperIDs.first
        }

        setSelection(paperIDs: validPaperIDs, primaryPaperID: validPrimaryPaperID)
    }

    private func togglePaperSelection(_ paper: Paper) {
        var nextSelection = selectedPaperIDs
        if nextSelection.contains(paper.id) {
            nextSelection.remove(paper.id)
            let nextPrimaryPaperID = selectedPaperID == paper.id
                ? displayedPapers.map(\.id).first(where: { nextSelection.contains($0) })
                : selectedPaperID
            setSelection(paperIDs: nextSelection, primaryPaperID: nextPrimaryPaperID)
        } else {
            nextSelection.insert(paper.id)
            setSelection(paperIDs: nextSelection, primaryPaperID: paper.id)
        }
        selectionAnchorPaperID = paper.id
    }

    private func selectRange(to paper: Paper, extendingCurrentSelection: Bool) {
        let anchorID = selectionAnchorPaperID
            ?? selectedPaperID
            ?? displayedPapers.map(\.id).first(where: { selectedPaperIDs.contains($0) })
            ?? paper.id

        guard let anchorIndex = displayedPapers.firstIndex(where: { $0.id == anchorID }),
              let targetIndex = displayedPapers.firstIndex(where: { $0.id == paper.id }) else {
            setSelection(paperIDs: [paper.id], primaryPaperID: paper.id)
            selectionAnchorPaperID = paper.id
            return
        }

        let bounds = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        let rangeIDs = Set(displayedPapers[bounds].map(\.id))
        let nextSelection = extendingCurrentSelection ? selectedPaperIDs.union(rangeIDs) : rangeIDs

        setSelection(paperIDs: nextSelection, primaryPaperID: paper.id)
        selectionAnchorPaperID = anchorID
    }

    private func setSelection(paperIDs: Set<String>, primaryPaperID: String?) {
        isSynchronizingSelection = true
        selectedPaperIDs = paperIDs
        selectedPaperID = primaryPaperID
        isSynchronizingSelection = false
    }

    private func openChatGPT() -> Bool {
        let fileManager = FileManager.default
        let bundleIDs = [
            "com.openai.chat",
            "com.openai.ChatGPT",
            "com.openai.chatgpt"
        ]

        for bundleID in bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.open(url)
                return true
            }
        }

        let appURLs = [
            URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/ChatGPT.app")
        ]

        for url in appURLs where fileManager.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
            return true
        }

        return false
    }

    private func present(_ error: Error) {
        alertMessage = AlertMessage(title: "PaperInbox Error", message: error.localizedDescription)
    }

    private func chatLinkKey(paperID: String, type: ArtifactType) -> String {
        "\(paperID)|\(type.rawValue)"
    }

    nonisolated private static func url(fromDroppedItem item: Any?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data,
           let string = String(data: data, encoding: .utf8) {
            return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let string = item as? String {
            return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}

import Foundation
import SQLiteShim

public enum PaperInboxStoreError: LocalizedError {
    case invalidURL(String)
    case paperNotFound(String)
    case collectionNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            return "This does not look like a valid URL: \(value)"
        case .paperNotFound(let id):
            return "No paper exists with ID \(id)."
        case .collectionNotFound(let id):
            return "No collection exists with ID \(id)."
        }
    }
}

public final class PaperInboxStore {
    private let database: DatabaseManager
    private let metadataService: MetadataService
    public let storage: FileStorageService

    public convenience init(storage: FileStorageService = FileStorageService()) throws {
        try storage.prepareStorage()
        try self.init(
            database: DatabaseManager(databaseURL: storage.databaseURL),
            storage: storage,
            metadataService: MetadataService()
        )
    }

    init(
        database: DatabaseManager,
        storage: FileStorageService,
        metadataService: MetadataService = MetadataService()
    ) {
        self.database = database
        self.storage = storage
        self.metadataService = metadataService
    }

    public func loadSnapshot() throws -> LibrarySnapshot {
        LibrarySnapshot(
            papers: try allPapers(),
            collections: try allCollections(),
            memberships: try allMemberships(),
            artifacts: try allArtifacts(),
            artifactChatLinks: try allArtifactChatLinks()
        )
    }

    public func createPaperFromPDF(
        sourceURL: URL,
        title: String? = nil,
        collectionIDs: [String] = []
    ) throws -> Paper {
        let paperID = try nextPaperID()
        let destinationURL = try storage.copyPDF(from: sourceURL, paperID: paperID)
        let fallbackTitle = FileTypeUtils.titleFromPDFURL(sourceURL)
        let metadata = metadataService.metadata(forPDF: destinationURL, filenameTitle: fallbackTitle)
        let now = Date()
        let paper = Paper(
            id: paperID,
            title: normalizedTitle(title) ?? metadata.title ?? fallbackTitle,
            authors: metadata.authors,
            year: metadata.year,
            venue: metadata.venue,
            abstract: metadata.abstract,
            localPDFPath: destinationURL.path,
            status: .unread,
            isHidden: false,
            createdAt: now,
            updatedAt: now
        )

        try database.transaction {
            try insertPaper(paper)
            try setCollections(collectionIDs, forPaperID: paper.id)
        }
        try storage.writeMetadata(paper)
        return paper
    }

    public func createPaperFromURL(
        _ rawURL: String,
        title: String? = nil,
        collectionIDs: [String] = []
    ) throws -> Paper {
        let url = try validatedURL(from: rawURL)
        let metadata = metadataService.metadata(forSourceURL: url)
        return try createPaperFromURL(
            url,
            title: title,
            collectionIDs: collectionIDs,
            metadata: metadata
        )
    }

    public func createPaperFromURL(
        _ rawURL: String,
        title: String? = nil,
        collectionIDs: [String] = [],
        allowNetworkMetadataLookup: Bool
    ) async throws -> Paper {
        let url = try validatedURL(from: rawURL)
        let metadata = await metadataService.metadata(
            forSourceURL: url,
            allowNetwork: allowNetworkMetadataLookup
        )
        return try createPaperFromURL(
            url,
            title: title,
            collectionIDs: collectionIDs,
            metadata: metadata
        )
    }

    @discardableResult
    public func refreshMetadata(paperID: String) throws -> Paper {
        guard var paper = try paper(id: paperID) else {
            throw PaperInboxStoreError.paperNotFound(paperID)
        }

        let metadata: ExtractedPaperMetadata
        if let localPDFPath = paper.localPDFPath,
           FileManager.default.fileExists(atPath: localPDFPath) {
            let url = URL(fileURLWithPath: localPDFPath)
            metadata = metadataService.metadata(
                forPDF: url,
                filenameTitle: FileTypeUtils.titleFromPDFURL(url)
            )
        } else if let sourceURL = paper.sourceURL,
                  let url = URL(string: sourceURL) {
            metadata = metadataService.metadata(forSourceURL: url)
        } else {
            return paper
        }

        merge(metadata, into: &paper)
        try updatePaper(paper)
        return paper
    }

    @discardableResult
    public func refreshMetadata(
        paperID: String,
        allowNetworkMetadataLookup: Bool
    ) async throws -> Paper {
        guard var paper = try paper(id: paperID) else {
            throw PaperInboxStoreError.paperNotFound(paperID)
        }

        let metadata: ExtractedPaperMetadata
        if let localPDFPath = paper.localPDFPath,
           FileManager.default.fileExists(atPath: localPDFPath) {
            let url = URL(fileURLWithPath: localPDFPath)
            metadata = metadataService.metadata(
                forPDF: url,
                filenameTitle: FileTypeUtils.titleFromPDFURL(url)
            )
        } else if let sourceURL = paper.sourceURL,
                  let url = URL(string: sourceURL) {
            metadata = await metadataService.metadata(
                forSourceURL: url,
                allowNetwork: allowNetworkMetadataLookup
            )
        } else {
            return paper
        }

        merge(metadata, into: &paper)
        try updatePaper(paper)
        return paper
    }

    public func updatePaper(_ paper: Paper) throws {
        var updated = paper
        updated.updatedAt = Date()

        try database.transaction {
            try updatePaperRow(updated)
            try rebuildSearchIndex(forPaperID: updated.id)
        }
        try storage.writeMetadata(updated)
    }

    public func updateStatus(paperID: String, status: PaperStatus) throws {
        guard var paper = try paper(id: paperID) else {
            throw PaperInboxStoreError.paperNotFound(paperID)
        }
        paper.status = status
        paper.isHidden = status.isHiddenByDefault
        try updatePaper(paper)
    }

    public func recordLaunch(paperID: String) throws {
        guard var paper = try paper(id: paperID) else {
            throw PaperInboxStoreError.paperNotFound(paperID)
        }
        paper.lastLaunchedAt = Date()
        try updatePaper(paper)
    }

    public func deletePaper(id: String) throws {
        try database.transaction {
            try database.execute("DELETE FROM papers WHERE id = ?;", bindings: [.text(id)])
            try database.execute("DELETE FROM paper_search WHERE paper_id = ?;", bindings: [.text(id)])
        }
        try storage.removePaperFolder(paperID: id)
    }

    public func createCollection(name: String) throws -> PaperCollection {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let collection = PaperCollection(name: trimmed, createdAt: now, updatedAt: now)
        try database.execute(
            """
            INSERT INTO collections (id, name, created_at, updated_at)
            VALUES (?, ?, ?, ?);
            """,
            bindings: [
                .text(collection.id),
                .text(collection.name),
                .text(DateCoding.string(from: collection.createdAt)),
                .text(DateCoding.string(from: collection.updatedAt))
            ]
        )
        return collection
    }

    public func renameCollection(id: String, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try database.execute(
            """
            UPDATE collections
            SET name = ?, updated_at = ?
            WHERE id = ?;
            """,
            bindings: [
                .text(trimmed),
                .text(DateCoding.string(from: Date())),
                .text(id)
            ]
        )
    }

    public func deleteCollection(id: String) throws {
        try database.execute("DELETE FROM collections WHERE id = ?;", bindings: [.text(id)])
    }

    public func setCollections(_ collectionIDs: [String], forPaperID paperID: String) throws {
        try database.execute(
            "DELETE FROM paper_collections WHERE paper_id = ?;",
            bindings: [.text(paperID)]
        )
        for collectionID in Set(collectionIDs) {
            try database.execute(
                """
                INSERT OR IGNORE INTO paper_collections (paper_id, collection_id)
                VALUES (?, ?);
                """,
                bindings: [.text(paperID), .text(collectionID)]
            )
        }
    }

    public func setCollectionMembership(
        paperID: String,
        collectionID: String,
        isMember: Bool
    ) throws {
        if isMember {
            try database.execute(
                """
                INSERT OR IGNORE INTO paper_collections (paper_id, collection_id)
                VALUES (?, ?);
                """,
                bindings: [.text(paperID), .text(collectionID)]
            )
        } else {
            try database.execute(
                """
                DELETE FROM paper_collections
                WHERE paper_id = ? AND collection_id = ?;
                """,
                bindings: [.text(paperID), .text(collectionID)]
            )
        }
    }

    @discardableResult
    public func saveArtifact(
        paperID: String,
        type: ArtifactType,
        contentMarkdown: String,
        source: ArtifactSource
    ) throws -> Artifact {
        guard var paper = try paper(id: paperID) else {
            throw PaperInboxStoreError.paperNotFound(paperID)
        }

        let now = Date()
        let artifact = Artifact(
            paperID: paperID,
            type: type,
            contentMarkdown: contentMarkdown.trimmingCharacters(in: .whitespacesAndNewlines),
            source: source,
            createdAt: now,
            updatedAt: now
        )

        paper.lastImportedAt = now
        paper.updatedAt = now

        try database.transaction {
            try database.execute(
                """
                INSERT INTO artifacts (id, paper_id, type, content_markdown, source, chatgpt_url, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """,
                bindings: [
                    .text(artifact.id),
                    .text(artifact.paperID),
                    .text(artifact.type.rawValue),
                    .text(artifact.contentMarkdown),
                    .text(artifact.source.rawValue),
                    .text(artifact.chatGPTURL),
                    .text(DateCoding.string(from: artifact.createdAt)),
                    .text(DateCoding.string(from: artifact.updatedAt))
                ]
            )
            try updatePaperRow(paper)
            try rebuildSearchIndex(forPaperID: paperID)
        }

        try storage.writeArtifact(artifact)
        try storage.writeMetadata(paper)
        return artifact
    }

    public func updateArtifactChatGPTURL(artifactID: String, chatGPTURL: String?) throws {
        let trimmedURL = chatGPTURL?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedURL = trimmedURL?.isEmpty == false ? trimmedURL : nil
        let updatedAt = Date()

        try database.execute(
            """
            UPDATE artifacts
            SET chatgpt_url = ?, updated_at = ?
            WHERE id = ?;
            """,
            bindings: [
                .text(normalizedURL),
                .text(DateCoding.string(from: updatedAt)),
                .text(artifactID)
            ]
        )
    }

    public func updateArtifactChatGPTURL(
        paperID: String,
        type: ArtifactType,
        chatGPTURL: String?
    ) throws {
        let trimmedURL = chatGPTURL?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedURL = trimmedURL?.isEmpty == false ? trimmedURL : nil

        if let normalizedURL {
            try database.execute(
                """
                INSERT INTO artifact_chat_links (paper_id, type, chatgpt_url, updated_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(paper_id, type) DO UPDATE SET
                    chatgpt_url = excluded.chatgpt_url,
                    updated_at = excluded.updated_at;
                """,
                bindings: [
                    .text(paperID),
                    .text(type.rawValue),
                    .text(normalizedURL),
                    .text(DateCoding.string(from: Date()))
                ]
            )
        } else {
            try database.execute(
                """
                DELETE FROM artifact_chat_links
                WHERE paper_id = ? AND type = ?;
                """,
                bindings: [
                    .text(paperID),
                    .text(type.rawValue)
                ]
            )
        }
    }

    public func searchPapers(query rawQuery: String) throws -> [Paper] {
        let query = ftsQuery(from: rawQuery)
        guard !query.isEmpty else { return try allPapers() }

        return try database.query(
            """
            SELECT p.*
            FROM paper_search
            JOIN papers p ON p.id = paper_search.paper_id
            WHERE paper_search MATCH ?
            ORDER BY rank;
            """,
            bindings: [.text(query)],
            map: mapPaper
        )
    }
}

private extension PaperInboxStore {
    func normalizedTitle(_ title: String?) -> String? {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    func validatedURL(from rawURL: String) throws -> URL {
        guard let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            throw PaperInboxStoreError.invalidURL(rawURL)
        }
        return url
    }

    func createPaperFromURL(
        _ url: URL,
        title: String?,
        collectionIDs: [String],
        metadata: ExtractedPaperMetadata
    ) throws -> Paper {
        let paperID = try nextPaperID()
        let now = Date()
        let paper = Paper(
            id: paperID,
            title: normalizedTitle(title) ?? metadata.title ?? FileTypeUtils.titleFromSourceURL(url),
            authors: metadata.authors,
            year: metadata.year,
            venue: metadata.venue,
            abstract: metadata.abstract,
            sourceURL: url.absoluteString,
            status: .unread,
            isHidden: false,
            createdAt: now,
            updatedAt: now
        )

        try storage.createPaperFolder(paperID: paper.id)
        try database.transaction {
            try insertPaper(paper)
            try setCollections(collectionIDs, forPaperID: paper.id)
        }
        try storage.writeMetadata(paper)
        return paper
    }

    func merge(_ metadata: ExtractedPaperMetadata, into paper: inout Paper) {
        if let title = metadata.title, shouldReplaceTitle(paper.title, paper: paper) {
            paper.title = title
        }
        if paper.authors?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            paper.authors = metadata.authors
        }
        if paper.year == nil {
            paper.year = metadata.year
        }
        if paper.venue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            paper.venue = metadata.venue
        }
        if paper.abstract?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            paper.abstract = metadata.abstract
        }
    }

    func shouldReplaceTitle(_ title: String, paper: Paper) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        if trimmed.isEmpty || ["paper", "source", "untitled"].contains(lowercased) {
            return true
        }

        if let sourceURL = paper.sourceURL,
           let url = URL(string: sourceURL),
           trimmed == FileTypeUtils.titleFromSourceURL(url) {
            return true
        }

        if trimmed.range(of: #"^\d{4}\.\d{4,5}(v\d+)?$"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }

    func nextPaperID(date: Date = Date()) throws -> String {
        let day = PaperIDGenerator.dayString(for: date)
        let rows = try database.query(
            "SELECT id FROM papers WHERE id LIKE ?;",
            bindings: [.text("P-\(day)-%")],
            map: { try DatabaseManager.requiredString($0, 0) }
        )
        return PaperIDGenerator.makeID(date: date, existingIDs: rows)
    }

    func insertPaper(_ paper: Paper) throws {
        try database.execute(
            """
            INSERT INTO papers (
                id, title, authors, year, venue, abstract, source_url, local_pdf_path,
                status, is_hidden, created_at, updated_at, last_launched_at, last_imported_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: paperBindings(paper)
        )
        try rebuildSearchIndex(forPaperID: paper.id)
    }

    func updatePaperRow(_ paper: Paper) throws {
        try database.execute(
            """
            UPDATE papers
            SET title = ?, authors = ?, year = ?, venue = ?, abstract = ?,
                source_url = ?, local_pdf_path = ?, status = ?, is_hidden = ?,
                created_at = ?, updated_at = ?, last_launched_at = ?, last_imported_at = ?
            WHERE id = ?;
            """,
            bindings: [
                .text(paper.title),
                .text(paper.authors),
                .int(paper.year),
                .text(paper.venue),
                .text(paper.abstract),
                .text(paper.sourceURL),
                .text(paper.localPDFPath),
                .text(paper.status.rawValue),
                .bool(paper.isHidden),
                .text(DateCoding.string(from: paper.createdAt)),
                .text(DateCoding.string(from: paper.updatedAt)),
                .text(paper.lastLaunchedAt.map(DateCoding.string)),
                .text(paper.lastImportedAt.map(DateCoding.string)),
                .text(paper.id)
            ]
        )
    }

    func paperBindings(_ paper: Paper) -> [SQLiteValue] {
        [
            .text(paper.id),
            .text(paper.title),
            .text(paper.authors),
            .int(paper.year),
            .text(paper.venue),
            .text(paper.abstract),
            .text(paper.sourceURL),
            .text(paper.localPDFPath),
            .text(paper.status.rawValue),
            .bool(paper.isHidden),
            .text(DateCoding.string(from: paper.createdAt)),
            .text(DateCoding.string(from: paper.updatedAt)),
            .text(paper.lastLaunchedAt.map(DateCoding.string)),
            .text(paper.lastImportedAt.map(DateCoding.string))
        ]
    }

    func paper(id: String) throws -> Paper? {
        try database.query(
            "SELECT * FROM papers WHERE id = ? LIMIT 1;",
            bindings: [.text(id)],
            map: mapPaper
        ).first
    }

    func allPapers() throws -> [Paper] {
        try database.query(
            "SELECT * FROM papers ORDER BY updated_at DESC, created_at DESC;",
            map: mapPaper
        )
    }

    func allCollections() throws -> [PaperCollection] {
        try database.query(
            "SELECT id, name, created_at, updated_at FROM collections ORDER BY name COLLATE NOCASE;",
            map: { statement in
                PaperCollection(
                    id: try DatabaseManager.requiredString(statement, 0),
                    name: try DatabaseManager.requiredString(statement, 1),
                    createdAt: try DatabaseManager.date(statement, 2),
                    updatedAt: try DatabaseManager.date(statement, 3)
                )
            }
        )
    }

    func allMemberships() throws -> [PaperCollectionMembership] {
        try database.query(
            "SELECT paper_id, collection_id FROM paper_collections;",
            map: { statement in
                PaperCollectionMembership(
                    paperID: try DatabaseManager.requiredString(statement, 0),
                    collectionID: try DatabaseManager.requiredString(statement, 1)
                )
            }
        )
    }

    func allArtifacts() throws -> [Artifact] {
        try database.query(
            """
            SELECT id, paper_id, type, content_markdown, source, chatgpt_url, created_at, updated_at
            FROM artifacts
            ORDER BY updated_at DESC;
            """,
            map: mapArtifact
        )
    }

    func allArtifactChatLinks() throws -> [ArtifactChatLink] {
        let rows = try database.query(
            """
            SELECT paper_id, type, chatgpt_url, updated_at
            FROM artifact_chat_links;
            """,
            map: mapArtifactChatLink
        )

        let explicitKeys = Set(rows.map { "\($0.paperID)|\($0.type.rawValue)" })
        let legacyRows = try allArtifacts().compactMap { artifact -> ArtifactChatLink? in
            guard let chatGPTURL = artifact.chatGPTURL,
                  !chatGPTURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !explicitKeys.contains("\(artifact.paperID)|\(artifact.type.rawValue)") else {
                return nil
            }
            return ArtifactChatLink(
                paperID: artifact.paperID,
                type: artifact.type,
                chatGPTURL: chatGPTURL,
                updatedAt: artifact.updatedAt
            )
        }

        return rows + legacyRows
    }

    func artifacts(for paperID: String) throws -> [Artifact] {
        try database.query(
            """
            SELECT id, paper_id, type, content_markdown, source, chatgpt_url, created_at, updated_at
            FROM artifacts
            WHERE paper_id = ?
            ORDER BY updated_at DESC;
            """,
            bindings: [.text(paperID)],
            map: mapArtifact
        )
    }

    func rebuildSearchIndex(forPaperID paperID: String) throws {
        guard let paper = try paper(id: paperID) else { return }
        let artifactText = try artifacts(for: paperID)
            .map(\.contentMarkdown)
            .joined(separator: "\n\n")

        try database.execute(
            "DELETE FROM paper_search WHERE paper_id = ?;",
            bindings: [.text(paperID)]
        )
        try database.execute(
            """
            INSERT INTO paper_search (paper_id, title, authors, venue, abstract, source_url, artifact_text)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(paper.id),
                .text(paper.title),
                .text(paper.authors),
                .text(paper.venue),
                .text(paper.abstract),
                .text(paper.sourceURL),
                .text(artifactText)
            ]
        )
    }

    func mapPaper(_ statement: OpaquePointer) throws -> Paper {
        let status = PaperStatus.fromStoredValue(try DatabaseManager.requiredString(statement, 8))

        return Paper(
            id: try DatabaseManager.requiredString(statement, 0),
            title: try DatabaseManager.requiredString(statement, 1),
            authors: DatabaseManager.string(statement, 2),
            year: DatabaseManager.int(statement, 3),
            venue: DatabaseManager.string(statement, 4),
            abstract: DatabaseManager.string(statement, 5),
            sourceURL: DatabaseManager.string(statement, 6),
            localPDFPath: DatabaseManager.string(statement, 7),
            status: status,
            isHidden: DatabaseManager.bool(statement, 9),
            createdAt: try DatabaseManager.date(statement, 10),
            updatedAt: try DatabaseManager.date(statement, 11),
            lastLaunchedAt: try DatabaseManager.optionalDate(statement, 12),
            lastImportedAt: try DatabaseManager.optionalDate(statement, 13)
        )
    }

    func mapArtifact(_ statement: OpaquePointer) throws -> Artifact {
        let typeValue = try DatabaseManager.requiredString(statement, 2)
        let sourceValue = try DatabaseManager.requiredString(statement, 4)

        guard let type = ArtifactType(rawValue: typeValue) else {
            throw DatabaseError("Unknown artifact type: \(typeValue).")
        }
        guard let source = ArtifactSource(rawValue: sourceValue) else {
            throw DatabaseError("Unknown artifact source: \(sourceValue).")
        }

        return Artifact(
            id: try DatabaseManager.requiredString(statement, 0),
            paperID: try DatabaseManager.requiredString(statement, 1),
            type: type,
            contentMarkdown: try DatabaseManager.requiredString(statement, 3),
            source: source,
            chatGPTURL: DatabaseManager.string(statement, 5),
            createdAt: try DatabaseManager.date(statement, 6),
            updatedAt: try DatabaseManager.date(statement, 7)
        )
    }

    func mapArtifactChatLink(_ statement: OpaquePointer) throws -> ArtifactChatLink {
        let typeValue = try DatabaseManager.requiredString(statement, 1)
        guard let type = ArtifactType(rawValue: typeValue) else {
            throw DatabaseError("Unknown artifact link type: \(typeValue).")
        }

        return ArtifactChatLink(
            paperID: try DatabaseManager.requiredString(statement, 0),
            type: type,
            chatGPTURL: try DatabaseManager.requiredString(statement, 2),
            updatedAt: try DatabaseManager.date(statement, 3)
        )
    }

    func ftsQuery(from rawQuery: String) -> String {
        rawQuery
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { "\($0)*" }
            .joined(separator: " ")
    }
}

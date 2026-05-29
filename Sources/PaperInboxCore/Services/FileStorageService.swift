import Foundation

public enum FileStorageError: LocalizedError {
    case couldNotCreateStorage(URL)
    case couldNotCopyPDF(URL)
    case missingPDF(URL)

    public var errorDescription: String? {
        switch self {
        case .couldNotCreateStorage(let url):
            return "Could not create PaperInbox storage at \(url.path)."
        case .couldNotCopyPDF(let url):
            return "Could not copy PDF into PaperInbox storage: \(url.path)."
        case .missingPDF(let url):
            return "Missing PDF file at \(url.path)."
        }
    }
}

public final class FileStorageService {
    public let baseURL: URL

    public init(baseURL: URL? = nil) {
        if let baseURL {
            self.baseURL = baseURL
        } else {
            self.baseURL = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PaperInbox", isDirectory: true)
        }
    }

    public var databaseDirectoryURL: URL {
        baseURL.appendingPathComponent("Database", isDirectory: true)
    }

    public var databaseURL: URL {
        databaseDirectoryURL.appendingPathComponent("paperinbox.sqlite")
    }

    public var papersDirectoryURL: URL {
        baseURL.appendingPathComponent("Papers", isDirectory: true)
    }

    public var importsDirectoryURL: URL {
        baseURL.appendingPathComponent("Imports", isDirectory: true)
    }

    public func prepareStorage() throws {
        do {
            try FileManager.default.createDirectory(
                at: databaseDirectoryURL,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: papersDirectoryURL,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: importsDirectoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw FileStorageError.couldNotCreateStorage(baseURL)
        }
    }

    public func paperFolderURL(for paperID: String) -> URL {
        papersDirectoryURL.appendingPathComponent(paperID, isDirectory: true)
    }

    public func localPDFURL(for paperID: String) -> URL {
        paperFolderURL(for: paperID).appendingPathComponent("paper.pdf")
    }

    public func artifactURL(for paperID: String, type: ArtifactType) -> URL {
        paperFolderURL(for: paperID).appendingPathComponent(type.markdownFilename)
    }

    public func metadataURL(for paperID: String) -> URL {
        paperFolderURL(for: paperID).appendingPathComponent("metadata.json")
    }

    public func createPaperFolder(paperID: String) throws {
        try FileManager.default.createDirectory(
            at: paperFolderURL(for: paperID),
            withIntermediateDirectories: true
        )
    }

    public func copyPDF(from sourceURL: URL, paperID: String) throws -> URL {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw FileStorageError.missingPDF(sourceURL)
        }

        try createPaperFolder(paperID: paperID)
        let destinationURL = localPDFURL(for: paperID)

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            throw FileStorageError.couldNotCopyPDF(sourceURL)
        }
    }

    public func writeMetadata(_ paper: Paper) throws {
        try createPaperFolder(paperID: paper.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(paper)
        try data.write(to: metadataURL(for: paper.id), options: .atomic)
    }

    public func writeArtifact(_ artifact: Artifact) throws {
        try createPaperFolder(paperID: artifact.paperID)
        try artifact.contentMarkdown.write(
            to: artifactURL(for: artifact.paperID, type: artifact.type),
            atomically: true,
            encoding: .utf8
        )
    }

    public func removePaperFolder(paperID: String) throws {
        let folderURL = paperFolderURL(for: paperID)
        if FileManager.default.fileExists(atPath: folderURL.path) {
            try FileManager.default.removeItem(at: folderURL)
        }
    }
}

import Foundation

public struct Paper: Identifiable, Codable, Equatable {
    public let id: String
    public var title: String
    public var authors: String?
    public var year: Int?
    public var venue: String?
    public var abstract: String?
    public var sourceURL: String?
    public var localPDFPath: String?
    public var status: PaperStatus
    public var isHidden: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var lastLaunchedAt: Date?
    public var lastImportedAt: Date?

    public init(
        id: String,
        title: String,
        authors: String? = nil,
        year: Int? = nil,
        venue: String? = nil,
        abstract: String? = nil,
        sourceURL: String? = nil,
        localPDFPath: String? = nil,
        status: PaperStatus = .unread,
        isHidden: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastLaunchedAt: Date? = nil,
        lastImportedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.authors = authors
        self.year = year
        self.venue = venue
        self.abstract = abstract
        self.sourceURL = sourceURL
        self.localPDFPath = localPDFPath
        self.status = status
        self.isHidden = isHidden
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastLaunchedAt = lastLaunchedAt
        self.lastImportedAt = lastImportedAt
    }
}

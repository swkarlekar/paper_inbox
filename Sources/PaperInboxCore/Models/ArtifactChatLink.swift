import Foundation

public struct ArtifactChatLink: Codable, Equatable, Hashable {
    public let paperID: String
    public let type: ArtifactType
    public var chatGPTURL: String
    public var updatedAt: Date

    public init(
        paperID: String,
        type: ArtifactType,
        chatGPTURL: String,
        updatedAt: Date = Date()
    ) {
        self.paperID = paperID
        self.type = type
        self.chatGPTURL = chatGPTURL
        self.updatedAt = updatedAt
    }
}

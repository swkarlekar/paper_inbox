import Foundation

public struct LibrarySnapshot: Equatable {
    public var papers: [Paper]
    public var collections: [PaperCollection]
    public var memberships: [PaperCollectionMembership]
    public var artifacts: [Artifact]
    public var artifactChatLinks: [ArtifactChatLink]

    public init(
        papers: [Paper] = [],
        collections: [PaperCollection] = [],
        memberships: [PaperCollectionMembership] = [],
        artifacts: [Artifact] = [],
        artifactChatLinks: [ArtifactChatLink] = []
    ) {
        self.papers = papers
        self.collections = collections
        self.memberships = memberships
        self.artifacts = artifacts
        self.artifactChatLinks = artifactChatLinks
    }
}

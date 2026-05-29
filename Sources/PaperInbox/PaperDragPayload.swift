import Foundation
import UniformTypeIdentifiers

enum PaperDragPayload {
    static let type = UTType(exportedAs: "local.paperinbox.paper-id")

    private static let fallbackPrefix = "paperinbox-paper-id:"

    static func provider(for paperID: String) -> NSItemProvider {
        provider(for: [paperID])
    }

    static func provider(for paperIDs: [String]) -> NSItemProvider {
        let uniquePaperIDs = deduplicated(paperIDs)
        let fallbackText = uniquePaperIDs
            .map { "\(fallbackPrefix)\($0)" }
            .joined(separator: "\n")
        let provider = NSItemProvider(object: fallbackText as NSString)
        provider.suggestedName = uniquePaperIDs.count == 1 ? uniquePaperIDs[0] : "\(uniquePaperIDs.count) papers"
        provider.registerDataRepresentation(
            forTypeIdentifier: type.identifier,
            visibility: .ownProcess
        ) { completion in
            completion(Data(uniquePaperIDs.joined(separator: "\n").utf8), nil)
            return nil
        }
        return provider
    }

    static func paperIDs(from data: Data) -> [String] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return deduplicated(
            text.components(separatedBy: .newlines).compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    static func paperIDs(fromText text: String) -> [String] {
        deduplicated(text.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix(fallbackPrefix) else { return nil }

            let id = trimmed.dropFirst(fallbackPrefix.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? nil : id
        })
    }

    private static func deduplicated(_ paperIDs: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for paperID in paperIDs {
            guard seen.insert(paperID).inserted else { continue }
            result.append(paperID)
        }

        return result
    }
}

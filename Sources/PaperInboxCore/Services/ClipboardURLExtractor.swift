import Foundation

public struct ClipboardURLExtractor {
    public init() {}

    public func allURLs(from text: String) -> [URL] {
        uniqueURLs(from: detectedURLStrings(in: text).compactMap(URL.init(string:)))
    }

    public func paperURLs(from text: String) -> [URL] {
        let urls = allURLs(from: text)
        let arxivURLs = uniqueURLs(from: urls.compactMap(canonicalArXivURL))
        return arxivURLs.isEmpty ? urls : arxivURLs
    }

    public func canonicalPaperURLString(for rawURL: String) -> String? {
        guard let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return (canonicalArXivURL(from: url) ?? url).absoluteString
    }

    private func detectedURLStrings(in text: String) -> [String] {
        let decoded = text.decodingClipboardHTMLEntities()
        let pattern = #"https?://[^\s<>\]\)"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(decoded.startIndex..<decoded.endIndex, in: decoded)
        return regex.matches(in: decoded, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: decoded) else { return nil }
            let candidate = String(decoded[matchRange])
                .trimmingCharacters(in: Self.trailingURLPunctuation)
            return candidate.isEmpty ? nil : candidate
        }
    }

    private func canonicalArXivURL(from url: URL) -> URL? {
        guard (url.host ?? "").lowercased().contains("arxiv.org"),
              let id = arXivID(from: url) else {
            return nil
        }
        return URL(string: "https://arxiv.org/abs/\(id)")
    }

    private func arXivID(from url: URL) -> String? {
        let path = url.path
            .replacingOccurrences(of: ".pdf", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = path.split(separator: "/").map(String.init)

        if let markerIndex = components.firstIndex(where: { ["abs", "pdf"].contains($0.lowercased()) }),
           components.indices.contains(markerIndex + 1) {
            return components[(markerIndex + 1)...].joined(separator: "/")
        }

        return components.last
    }

    private func uniqueURLs(from urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var unique: [URL] = []

        for url in urls {
            let key = url.absoluteString
            guard seen.insert(key).inserted else { continue }
            unique.append(url)
        }

        return unique
    }

    private static let trailingURLPunctuation = CharacterSet(charactersIn: ".,;:!?")
}

private extension String {
    func decodingClipboardHTMLEntities() -> String {
        var value = self
        let entities = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&nbsp;": " "
        ]

        for (entity, replacement) in entities {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }

        return value
    }
}

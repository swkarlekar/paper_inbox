import Foundation
import PDFKit

public struct ExtractedPaperMetadata: Equatable {
    public var title: String?
    public var authors: String?
    public var year: Int?
    public var venue: String?
    public var abstract: String?

    public init(
        title: String? = nil,
        authors: String? = nil,
        year: Int? = nil,
        venue: String? = nil,
        abstract: String? = nil
    ) {
        self.title = title
        self.authors = authors
        self.year = year
        self.venue = venue
        self.abstract = abstract
    }

    func fillingMissingValues(from fallback: ExtractedPaperMetadata) -> ExtractedPaperMetadata {
        ExtractedPaperMetadata(
            title: title ?? fallback.title,
            authors: authors ?? fallback.authors,
            year: year ?? fallback.year,
            venue: venue ?? fallback.venue,
            abstract: abstract ?? fallback.abstract
        )
    }
}

public struct MetadataService {
    public init() {}

    public func metadata(forPDF url: URL, filenameTitle: String? = nil) -> ExtractedPaperMetadata {
        guard let document = PDFDocument(url: url) else {
            return ExtractedPaperMetadata()
        }

        let attributes = document.documentAttributes ?? [:]
        let filename = filenameTitle ?? FileTypeUtils.titleFromPDFURL(url)
        let pageText = firstPagesText(from: document)

        let titleAttribute = clean(attributes[PDFDocumentAttribute.titleAttribute] as? String)
        let authorAttribute = cleanAuthors(attributes[PDFDocumentAttribute.authorAttribute] as? String)
        let subjectAttribute = clean(attributes[PDFDocumentAttribute.subjectAttribute] as? String)
        let creationDate = attributes[PDFDocumentAttribute.creationDateAttribute] as? Date

        let title = usefulTitle(titleAttribute, fallbackTitle: filename)
            ?? inferTitle(from: pageText, fallbackTitle: filename)

        let abstract = usefulAbstract(subjectAttribute)
            ?? inferAbstract(from: pageText)

        return ExtractedPaperMetadata(
            title: title,
            authors: authorAttribute ?? inferAuthors(from: pageText, title: title),
            year: inferYear(from: pageText + "\n" + filename) ?? creationDate.flatMap(publicationYear),
            venue: inferVenue(from: pageText),
            abstract: abstract
        )
    }

    public func metadata(forSourceURL url: URL) -> ExtractedPaperMetadata {
        if let arxivID = arXivID(from: url) {
            return ExtractedPaperMetadata(
                title: "arXiv:\(arxivID)",
                year: yearFromArXivID(arxivID),
                venue: "arXiv"
            )
        }

        if let doi = doi(from: url) {
            return ExtractedPaperMetadata(
                title: "DOI: \(doi)",
                venue: "DOI"
            )
        }

        if let pubMedID = pubMedID(from: url) {
            return ExtractedPaperMetadata(
                title: "PubMed: \(pubMedID)",
                venue: "PubMed"
            )
        }

        return ExtractedPaperMetadata(
            title: FileTypeUtils.titleFromSourceURL(url),
            year: inferYear(from: url.absoluteString)
        )
    }

    public func metadata(forSourceURL url: URL, allowNetwork: Bool) async -> ExtractedPaperMetadata {
        let fallback = metadata(forSourceURL: url)
        guard allowNetwork else { return fallback }

        if let arxivID = arXivID(from: url),
           let metadata = try? await fetchArXivMetadata(id: arxivID) {
            return metadata.fillingMissingValues(from: fallback)
        }

        if let doi = doi(from: url),
           let metadata = try? await fetchDOIMetadata(doi: doi) {
            return metadata.fillingMissingValues(from: fallback)
        }

        if let metadata = try? await fetchHTMLMetadata(url: url) {
            return metadata.fillingMissingValues(from: fallback)
        }

        return fallback
    }
}

private extension MetadataService {
    func fetchArXivMetadata(id: String) async throws -> ExtractedPaperMetadata {
        var components = URLComponents(string: "https://export.arxiv.org/api/query")!
        components.queryItems = [
            URLQueryItem(name: "id_list", value: id)
        ]
        let url = components.url!
        let data = try await fetch(url: url, accept: "application/atom+xml")
        let parser = ArXivAtomParser()
        let result = try parser.parse(data)

        return ExtractedPaperMetadata(
            title: clean(result.title),
            authors: cleanAuthors(result.authors.joined(separator: ", ")),
            year: result.published.flatMap(inferYear(from:)) ?? yearFromArXivID(id),
            venue: "arXiv",
            abstract: usefulAbstract(result.summary)
        )
    }

    func fetchDOIMetadata(doi: String) async throws -> ExtractedPaperMetadata {
        let encodedDOI = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? doi
        let url = URL(string: "https://doi.org/\(encodedDOI)")!
        let data = try await fetch(url: url, accept: "application/vnd.citationstyles.csl+json")
        let csl = try JSONDecoder().decode(CSLItem.self, from: data)

        return ExtractedPaperMetadata(
            title: csl.primaryTitle,
            authors: csl.authorNames,
            year: csl.issuedYear,
            venue: csl.venue,
            abstract: usefulAbstract(csl.abstract)
        )
    }

    func fetchHTMLMetadata(url: URL) async throws -> ExtractedPaperMetadata {
        let data = try await fetch(url: url, accept: "text/html,application/xhtml+xml")
        let html = String(decoding: data.prefix(1_500_000), as: UTF8.self)
        let metadata = HTMLMetadataParser(html: html)

        return ExtractedPaperMetadata(
            title: clean(
                metadata.value(for: "citation_title")
                    ?? metadata.value(for: "dc.title")
                    ?? metadata.value(property: "og:title")
                    ?? metadata.titleTag
            ),
            authors: metadata.values(for: "citation_author").isEmpty
                ? nil
                : metadata.values(for: "citation_author").joined(separator: ", "),
            year: metadata.value(for: "citation_publication_date")
                .flatMap(inferYear(from:))
                ?? metadata.value(for: "citation_online_date").flatMap(inferYear(from:))
                ?? metadata.value(for: "dc.date").flatMap(inferYear(from:)),
            venue: clean(
                metadata.value(for: "citation_journal_title")
                    ?? metadata.value(for: "citation_conference_title")
                    ?? metadata.value(for: "citation_publisher")
            ),
            abstract: usefulAbstract(
                metadata.value(for: "citation_abstract")
                    ?? metadata.value(for: "dc.description")
                    ?? metadata.value(for: "description")
                    ?? metadata.value(property: "og:description")
            )
        )
    }

    func fetch(url: URL, accept: String) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("PaperInbox/0.1 (local macOS app)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    func firstPagesText(from document: PDFDocument, maxPages: Int = 3) -> String {
        guard document.pageCount > 0 else { return "" }
        return (0..<min(document.pageCount, maxPages))
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
    }

    func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value
            .removingHTMLTags()
            .decodingBasicHTMLEntities()
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    func cleanAuthors(_ value: String?) -> String? {
        guard let cleaned = clean(value) else { return nil }
        let lowercased = cleaned.lowercased()
        guard !lowercased.contains("anonymous"),
              !lowercased.contains("unknown") else {
            return nil
        }
        return cleaned
    }

    func usefulTitle(_ value: String?, fallbackTitle: String) -> String? {
        guard let value = clean(value) else { return nil }
        let lowercased = value.lowercased()
        let fallback = fallbackTitle.lowercased()

        guard value.count >= 6,
              value.count <= 220,
              lowercased != "untitled",
              lowercased != fallback,
              !lowercased.contains("microsoft word"),
              !lowercased.contains("powerpoint"),
              !lowercased.contains(".pdf") else {
            return nil
        }

        return value
    }

    func usefulAbstract(_ value: String?) -> String? {
        guard let value = clean(value), value.count >= 80 else { return nil }
        return value.count > 2_500 ? String(value.prefix(2_500)) : value
    }

    func inferTitle(from text: String, fallbackTitle: String) -> String? {
        let lines = candidateLines(from: text)
        guard !lines.isEmpty else { return nil }

        var titleLines: [String] = []
        for line in lines.prefix(12) {
            let lowercased = line.lowercased()
            if lowercased == "abstract" || lowercased.hasPrefix("abstract ") {
                break
            }
            if shouldSkipHeaderLine(line) {
                continue
            }
            if !titleLines.isEmpty && isLikelyAuthorOrAffiliationLine(line) {
                break
            }

            titleLines.append(line)
            if titleLines.count == 3 || titleLines.joined(separator: " ").count > 180 {
                break
            }
        }

        return usefulTitle(titleLines.joined(separator: " "), fallbackTitle: fallbackTitle)
    }

    func inferAuthors(from text: String, title: String?) -> String? {
        let lines = candidateLines(from: text)
        guard !lines.isEmpty else { return nil }

        let titleWords = Set((title ?? "")
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty })

        for line in lines.prefix(18) {
            let lowercased = line.lowercased()
            if lowercased == "abstract" || lowercased.hasPrefix("abstract ") {
                break
            }
            if shouldSkipHeaderLine(line) {
                continue
            }

            let lineWords = Set(lowercased
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty })
            if !titleWords.isEmpty && lineWords.isSubset(of: titleWords) {
                continue
            }

            if isLikelyAuthorLine(line) {
                return cleanAuthors(line)
            }
        }

        return nil
    }

    func inferAbstract(from text: String) -> String? {
        let normalized = text.replacingOccurrences(of: "\r", with: "\n")
        guard let abstractRange = normalized.range(
            of: #"(?i)\babstract\b[:\s\n-]*"#,
            options: .regularExpression
        ) else {
            return nil
        }

        let tail = String(normalized[abstractRange.upperBound...].prefix(4_000))
        let stopPatterns = [
            #"(?im)\n\s*(?:1\.?\s+)?(?:introduction|background|preliminaries|related work)\b"#,
            #"(?m)\n\s*(?:1|I)\.?\s+[A-Z][A-Za-z ]{3,}"#
        ]

        let stopIndex = stopPatterns
            .compactMap { pattern -> String.Index? in
                tail.range(of: pattern, options: .regularExpression)?.lowerBound
            }
            .min()

        let abstractText = stopIndex.map { String(tail[..<$0]) } ?? tail
        return usefulAbstract(abstractText)
    }

    func inferVenue(from text: String) -> String? {
        let lines = candidateLines(from: text).prefix(30)
        let joined = lines.joined(separator: " ")
        let patterns = [
            #"(?i)\bNeurIPS\b|\bNIPS\b"#: "NeurIPS",
            #"(?i)\bICML\b"#: "ICML",
            #"(?i)\bICLR\b"#: "ICLR",
            #"(?i)\bACL\b"#: "ACL",
            #"(?i)\bEMNLP\b"#: "EMNLP",
            #"(?i)\bCVPR\b"#: "CVPR",
            #"(?i)\bICCV\b"#: "ICCV",
            #"(?i)\bECCV\b"#: "ECCV",
            #"(?i)\bAAAI\b"#: "AAAI",
            #"(?i)\bKDD\b"#: "KDD",
            #"(?i)\bSIGGRAPH\b"#: "SIGGRAPH",
            #"(?i)\bProceedings of Machine Learning Research\b|\bPMLR\b"#: "PMLR",
            #"(?i)\barXiv\b"#: "arXiv"
        ]

        for (pattern, venue) in patterns {
            if joined.range(of: pattern, options: .regularExpression) != nil {
                return venue
            }
        }
        return nil
    }

    func inferYear(from text: String) -> Int? {
        guard let range = text.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression),
              let year = Int(text[range]) else {
            return nil
        }
        return (1900...2100).contains(year) ? year : nil
    }

    func publicationYear(from date: Date) -> Int? {
        Calendar.current.dateComponents([.year], from: date).year
    }

    func candidateLines(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { clean($0) }
            .compactMap { $0 }
            .filter { $0.count >= 3 && $0.count <= 260 }
    }

    func shouldSkipHeaderLine(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        return lowercased.hasPrefix("arxiv:")
            || lowercased.hasPrefix("doi:")
            || lowercased.contains("published as")
            || lowercased.contains("proceedings of")
            || lowercased.contains("conference on")
            || lowercased.contains("workshop on")
            || lowercased.contains("preprint")
            || lowercased.contains("copyright")
            || lowercased.contains("all rights reserved")
    }

    func isLikelyAuthorOrAffiliationLine(_ line: String) -> Bool {
        isLikelyAuthorLine(line) || isLikelyAffiliationLine(line)
    }

    func isLikelyAuthorLine(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        guard !lowercased.contains("abstract") else { return false }
        if lowercased.contains("@") { return false }
        if isLikelyAffiliationLine(line) { return false }

        let commaCount = line.filter { $0 == "," }.count
        let hasAuthorConnector = lowercased.contains(" and ") || commaCount >= 1
        let words = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let capitalizedWords = words.filter { word in
            guard let first = word.first else { return false }
            return first.isUppercase
        }

        return hasAuthorConnector
            && words.count <= 28
            && capitalizedWords.count >= max(1, min(words.count, 3))
    }

    func isLikelyAffiliationLine(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        return lowercased.contains("university")
            || lowercased.contains("institute")
            || lowercased.contains("department")
            || lowercased.contains("school of")
            || lowercased.contains("laboratory")
            || lowercased.contains("google")
            || lowercased.contains("microsoft")
            || lowercased.contains("meta ai")
            || lowercased.contains("openai")
    }

    func arXivID(from url: URL) -> String? {
        guard (url.host ?? "").lowercased().contains("arxiv.org") else { return nil }
        let path = url.path
            .replacingOccurrences(of: ".pdf", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = path.split(separator: "/").map(String.init)

        if let absIndex = components.firstIndex(where: { ["abs", "pdf"].contains($0.lowercased()) }),
           components.indices.contains(absIndex + 1) {
            return components[(absIndex + 1)...].joined(separator: "/")
        }

        return components.last
    }

    func yearFromArXivID(_ id: String) -> Int? {
        guard let range = id.range(of: #"^\d{4}"#, options: .regularExpression) else {
            return nil
        }
        let prefix = String(id[range])
        guard let yy = Int(prefix.prefix(2)) else { return nil }
        return yy >= 91 ? 1900 + yy : 2000 + yy
    }

    func doi(from url: URL) -> String? {
        let host = (url.host ?? "").lowercased()
        if host.contains("doi.org") {
            return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .removingPercentEncoding
        }

        let absolute = url.absoluteString
        guard let range = absolute.range(
            of: #"10\.\d{4,9}/[-._;()/:A-Za-z0-9]+"#,
            options: .regularExpression
        ) else {
            return nil
        }
        return String(absolute[range])
    }

    func pubMedID(from url: URL) -> String? {
        let host = (url.host ?? "").lowercased()
        guard host.contains("pubmed.ncbi.nlm.nih.gov") else { return nil }
        return url.path
            .split(separator: "/")
            .first
            .map(String.init)
    }
}

private final class ArXivAtomParser: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var currentText = ""
    private var inEntry = false
    private var inAuthor = false
    private var didFinishFirstEntry = false

    private(set) var title: String?
    private(set) var summary: String?
    private(set) var published: String?
    private(set) var authors: [String] = []

    func parse(_ data: Data) throws -> ArXivAtomParser {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse(), title != nil || summary != nil || !authors.isEmpty else {
            throw parser.parserError ?? URLError(.cannotParseResponse)
        }
        return self
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard !didFinishFirstEntry else { return }
        currentElement = elementName
        currentText = ""
        if elementName == "entry" {
            inEntry = true
        } else if inEntry && elementName == "author" {
            inAuthor = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inEntry, !didFinishFirstEntry else { return }
        currentText.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard inEntry, !didFinishFirstEntry else { return }
        let value = currentText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if inAuthor && elementName == "name", !value.isEmpty {
            authors.append(value)
        } else if !inAuthor && elementName == "title" {
            title = value
        } else if !inAuthor && elementName == "summary" {
            summary = value
        } else if !inAuthor && elementName == "published" {
            published = value
        } else if elementName == "author" {
            inAuthor = false
        } else if elementName == "entry" {
            inEntry = false
            didFinishFirstEntry = true
        }

        currentText = ""
    }
}

private struct CSLItem: Decodable {
    struct Name: Decodable {
        var given: String?
        var family: String?
        var literal: String?
    }

    struct DateParts: Decodable {
        var dateParts: [[Int]]?

        enum CodingKeys: String, CodingKey {
            case dateParts = "date-parts"
        }
    }

    var title: FlexibleStringList?
    var author: [Name]?
    var issued: DateParts?
    var abstract: String?
    var containerTitle: FlexibleStringList?
    var publisher: String?

    enum CodingKeys: String, CodingKey {
        case title
        case author
        case issued
        case abstract
        case containerTitle = "container-title"
        case publisher
    }

    var primaryTitle: String? {
        title?.firstCleanValue
    }

    var authorNames: String? {
        let names = author?.compactMap { name -> String? in
            if let literal = name.literal, !literal.isEmpty {
                return literal
            }
            let value = [name.given, name.family]
                .compactMap { $0 }
                .joined(separator: " ")
            return value.isEmpty ? nil : value
        } ?? []
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    var issuedYear: Int? {
        issued?.dateParts?.first?.first
    }

    var venue: String? {
        containerTitle?.firstCleanValue ?? publisher
    }
}

private enum FlexibleStringList: Decodable {
    case string(String)
    case strings([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .strings((try? container.decode([String].self)) ?? [])
        }
    }

    var firstCleanValue: String? {
        switch self {
        case .string(let value):
            return value.isEmpty ? nil : value
        case .strings(let values):
            return values.first { !$0.isEmpty }
        }
    }
}

private struct HTMLMetadataParser {
    let html: String

    func value(for name: String) -> String? {
        values(for: name).first
    }

    func values(for name: String) -> [String] {
        metaValues(attribute: "name", value: name)
    }

    func value(property: String) -> String? {
        metaValues(attribute: "property", value: property).first
    }

    var titleTag: String? {
        guard let range = html.range(
            of: #"(?is)<title[^>]*>(.*?)</title>"#,
            options: .regularExpression
        ) else {
            return nil
        }
        let match = String(html[range])
        return match
            .replacingOccurrences(of: #"(?is)</?title[^>]*>"#, with: "", options: .regularExpression)
            .decodingBasicHTMLEntities()
    }

    private func metaValues(attribute: String, value: String) -> [String] {
        let escapedValue = NSRegularExpression.escapedPattern(for: value)
        let patterns = [
            #"(?is)<meta\b(?=[^>]*\b"# + attribute + #"\s*=\s*['"]"# + escapedValue + #"['"])(?=[^>]*\bcontent\s*=\s*['"]([^'"]*)['"])[^>]*>"#,
            #"(?is)<meta\b(?=[^>]*\bcontent\s*=\s*['"]([^'"]*)['"])(?=[^>]*\b"# + attribute + #"\s*=\s*['"]"# + escapedValue + #"['"])[^>]*>"#
        ]

        return patterns.flatMap { pattern -> [String] in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            return regex.matches(in: html, range: range).compactMap { match in
                guard let captureRange = Range(match.range(at: 1), in: html) else { return nil }
                return String(html[captureRange]).decodingBasicHTMLEntities()
            }
        }
    }
}

private extension String {
    func removingHTMLTags() -> String {
        replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
    }

    func decodingBasicHTMLEntities() -> String {
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

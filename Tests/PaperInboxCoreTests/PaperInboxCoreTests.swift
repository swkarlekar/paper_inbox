import XCTest
@testable import PaperInboxCore

final class PaperInboxCoreTests: XCTestCase {
    func testPaperIDGenerationIncrementsForDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_779_923_200) // 2026-05-28T00:00:00Z

        let id = PaperIDGenerator.makeID(
            date: date,
            existingIDs: [
                "P-2026-05-28-0001",
                "P-2026-05-28-0007",
                "P-2026-05-27-0042"
            ],
            calendar: calendar
        )

        XCTAssertEqual(id, "P-2026-05-28-0008")
    }

    func testPromptBuilderUsesWrapperAndPDFSourceFallback() {
        let paper = Paper(
            id: "P-2026-05-28-0007",
            title: "Representation Learning",
            localPDFPath: "/tmp/paper.pdf"
        )

        let prompt = PromptBuilder().buildSummaryPrompt(paper: paper)

        XCTAssertTrue(prompt.contains("Paper ID: P-2026-05-28-0007"))
        XCTAssertTrue(prompt.contains("[BEGIN PAPER SUMMARY: P-2026-05-28-0007]"))
        XCTAssertTrue(prompt.contains("[END PAPER SUMMARY: P-2026-05-28-0007]"))
        XCTAssertTrue(prompt.contains("Source: Attached local PDF. If no PDF is attached, ask me to attach it before proceeding."))
        XCTAssertFalse(prompt.contains("persistent paper-reading note"))
        XCTAssertFalse(prompt.contains("3–5 bullets"))
        XCTAssertTrue(prompt.contains("Use as many bullets as the paper needs"))
        XCTAssertTrue(prompt.contains("connecting the intuition to the math"))
        XCTAssertTrue(prompt.contains("Include both the intuitive reason for each component and the mathematical/formal version"))
    }

    func testClipboardParserParsesMultipleArtifacts() throws {
        let text = """
        Leading text.

        [BEGIN PAPER SUMMARY: P-2026-05-28-0007]

        # Summary

        Equation:
        \\[
        x = y
        \\]

        [END PAPER SUMMARY: P-2026-05-28-0007]

        [BEGIN STUDY GUIDE: P-2026-05-28-0007]
        # Guide
        [END STUDY GUIDE: P-2026-05-28-0007]
        """

        let artifacts = try ClipboardImportParser().parse(text)

        XCTAssertEqual(artifacts.count, 2)
        XCTAssertEqual(artifacts[0].type, .summary)
        XCTAssertEqual(artifacts[0].paperID, "P-2026-05-28-0007")
        XCTAssertTrue(artifacts[0].contentMarkdown.contains("\\[\nx = y\n\\]"))
        XCTAssertEqual(artifacts[1].type, .studyGuide)
    }

    func testClipboardParserRejectsMismatchedWrapperIDs() {
        let text = """
        [BEGIN PAPER SUMMARY: P-2026-05-28-0007]
        # Summary
        [END PAPER SUMMARY: P-2026-05-28-0008]
        """

        XCTAssertThrowsError(try ClipboardImportParser().parse(text)) { error in
            XCTAssertEqual(
                error as? ClipboardImportError,
                .malformedWrapper("Found a malformed wrapper. The BEGIN and END paper IDs do not match.")
            )
        }
    }

    func testClipboardURLExtractorPrefersArxivLinksFromMarkdownList() {
        let text = """
        * **Semformer: Transformer Language Models with Semantic Planning** <br>
        *Yongjing Yin, Junran Ding, Kai Song, Yue Zhang* <br>
        EMNLP, 2024. [[Paper]](https://arxiv.org/abs/2409.11143) [[Code]](https://github.com/ARIES-LM/Semformer.git)

        * **Large Concept Models: Language Modeling in a Sentence Representation Space** <br>
        arXiv, 2024. [[Paper]](https://arxiv.org/abs/2412.08821) [[Code]](https://github.com/facebookresearch/large_concept_model)

        * **LLM Pretraining with Continuous Concepts** <br>
        arXiv, 2025. [[Paper]](https://arxiv.org/abs/2502.08524) [[Code]](https://github.com/facebookresearch/RAM/tree/main/projects/cocomix)

        * **Beyond Multi-Token Prediction: Pretraining LLMs with Future Summaries** <br>
        ICLR, 2026. [[Paper]](https://arxiv.org/abs/2510.14751)

        * **Continuous Autoregressive Language Models** <br>
        arXiv, 2025. [[Paper]](https://arxiv.org/abs/2510.27688) [[Code]](https://github.com/shaochenze/calm) [[Website]](https://shaochenze.github.io/blog/2025/CALM)

        * **Next-Latent Prediction Transformers Learn Compact World Models** <br>
        arXiv, 2025. [[Paper]](https://arxiv.org/abs/2511.05963)

        * **Dynamic Large Concept Models: Latent Reasoning in an Adaptive Semantic Space** <br>
        arXiv, 2025. [[Paper]](https://arxiv.org/abs/2512.24617)

        * **Next Concept Prediction in Discrete Latent Space Leads to Stronger Language Models** <br>
        arXiv, 2026. [[Paper]](https://arxiv.org/abs/2602.08984) [[Code]](https://github.com/LUMIA-Group/ConceptLM)
        """

        let urls = ClipboardURLExtractor().paperURLs(from: text).map(\.absoluteString)

        XCTAssertEqual(urls, [
            "https://arxiv.org/abs/2409.11143",
            "https://arxiv.org/abs/2412.08821",
            "https://arxiv.org/abs/2502.08524",
            "https://arxiv.org/abs/2510.14751",
            "https://arxiv.org/abs/2510.27688",
            "https://arxiv.org/abs/2511.05963",
            "https://arxiv.org/abs/2512.24617",
            "https://arxiv.org/abs/2602.08984"
        ])
    }

    func testClipboardURLExtractorFallsBackToAllURLsWhenNoArxivLinksExist() {
        let text = "See https://example.com/paper and https://github.com/example/repo."

        let urls = ClipboardURLExtractor().paperURLs(from: text).map(\.absoluteString)

        XCTAssertEqual(urls, [
            "https://example.com/paper",
            "https://github.com/example/repo"
        ])
    }

    func testMetadataServiceParsesArxivURL() throws {
        let url = try XCTUnwrap(URL(string: "https://arxiv.org/abs/2605.00001"))

        let metadata = MetadataService().metadata(forSourceURL: url)

        XCTAssertEqual(metadata.title, "arXiv:2605.00001")
        XCTAssertEqual(metadata.venue, "arXiv")
        XCTAssertEqual(metadata.year, 2026)
    }

    func testStorePersistsURLPaperStatusCollectionAndSearch() throws {
        let harness = try StoreHarness()
        let store = harness.store

        let paper = try store.createPaperFromURL("https://arxiv.org/abs/2605.00001")
        XCTAssertEqual(paper.title, "arXiv:2605.00001")
        XCTAssertEqual(paper.venue, "arXiv")
        XCTAssertEqual(paper.year, 2026)

        let collection = try store.createCollection(name: "Reading Group")
        try store.setCollectionMembership(paperID: paper.id, collectionID: collection.id, isMember: true)
        try store.updateStatus(paperID: paper.id, status: .read)

        let snapshot = try store.loadSnapshot()
        XCTAssertEqual(snapshot.papers.count, 1)
        XCTAssertEqual(snapshot.papers[0].status, .read)
        XCTAssertTrue(snapshot.papers[0].isHidden)
        XCTAssertEqual(snapshot.collections.count, 1)
        XCTAssertEqual(snapshot.memberships.count, 1)

        let results = try store.searchPapers(query: "arxiv")
        XCTAssertEqual(results.map(\.id), [paper.id])

        try store.deleteCollection(id: collection.id)
        let afterDelete = try store.loadSnapshot()
        XCTAssertEqual(afterDelete.papers.count, 1)
        XCTAssertTrue(afterDelete.collections.isEmpty)
        XCTAssertTrue(afterDelete.memberships.isEmpty)
    }

    func testStoreCopiesPDFAndDeletesPaperFolder() throws {
        let harness = try StoreHarness()
        let sourcePDF = harness.root.appendingPathComponent("source.pdf")
        try Data("%PDF-1.4\n".utf8).write(to: sourcePDF)

        let paper = try harness.store.createPaperFromPDF(sourceURL: sourcePDF)
        let localPath = try XCTUnwrap(paper.localPDFPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: localPath))

        try harness.store.deletePaper(id: paper.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.storage.paperFolderURL(for: paper.id).path))
    }

    func testStorePersistsArtifactChatGPTURL() throws {
        let harness = try StoreHarness()
        let paper = try harness.store.createPaperFromURL("https://arxiv.org/abs/2605.00001")
        _ = try harness.store.saveArtifact(
            paperID: paper.id,
            type: .studyGuide,
            contentMarkdown: "# Guide",
            source: .clipboard
        )

        try harness.store.updateArtifactChatGPTURL(
            paperID: paper.id,
            type: .studyGuide,
            chatGPTURL: "https://chatgpt.com/share/example"
        )

        let snapshot = try harness.store.loadSnapshot()
        XCTAssertEqual(snapshot.artifactChatLinks.first?.chatGPTURL, "https://chatgpt.com/share/example")
    }
}

private final class StoreHarness {
    let root: URL
    let storage: FileStorageService
    let store: PaperInboxStore

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperInboxTests-\(UUID().uuidString)", isDirectory: true)
        storage = FileStorageService(baseURL: root)
        store = try PaperInboxStore(storage: storage)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }
}

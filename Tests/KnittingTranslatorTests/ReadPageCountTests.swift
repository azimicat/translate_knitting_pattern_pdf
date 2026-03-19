import XCTest
import PDFKit
@testable import KnittingTranslator

/// AppState.readPageCount(from:) のテスト
/// テスト用PDFはファイルシステムに書き出して使う（Security Scope 不要な一時ファイル）
@MainActor
final class ReadPageCountTests: XCTestCase {

    private var sut: AppState!
    private var tempDir: URL!

    override func setUp() async throws {
        sut     = AppState()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadPageCountTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        sut = nil
    }

    // MARK: - ヘルパー

    /// 指定ページ数の最小限PDFを一時ディレクトリに書き出してURLを返す
    private func makePDF(pageCount: Int) throws -> URL {
        let doc = PDFDocument()
        for _ in 0..<pageCount {
            let page = PDFPage()
            doc.insert(page, at: doc.pageCount)
        }
        let url = tempDir.appendingPathComponent("\(UUID().uuidString).pdf")
        guard let data = doc.dataRepresentation() else {
            throw XCTSkip("PDFDocument.dataRepresentation() が nil を返した")
        }
        try data.write(to: url)
        return url
    }

    // MARK: - テスト

    func testReadPageCount_singlePage() throws {
        let url = try makePDF(pageCount: 1)
        XCTAssertEqual(sut.readPageCount(from: url), 1)
    }

    func testReadPageCount_multiplePages() throws {
        let url = try makePDF(pageCount: 20)
        XCTAssertEqual(sut.readPageCount(from: url), 20)
    }

    func testReadPageCount_invalidURL_returnsZero() {
        let url = tempDir.appendingPathComponent("nonexistent.pdf")
        XCTAssertEqual(sut.readPageCount(from: url), 0)
    }
}

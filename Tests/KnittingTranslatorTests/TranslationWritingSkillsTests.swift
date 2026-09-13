import XCTest
@testable import KnittingTranslator

final class TranslationWritingSkillsTests: XCTestCase {
    func testBothSkillsAreBundledInDependencyOrder() throws {
        let text = try TranslationWritingSkills.instructions()
        let dependency = try XCTUnwrap(text.range(of: "# 日本語技術文書の文章規範"))
        let requested = try XCTUnwrap(text.range(of: "# 認知リズムを生むための日本語ライティング規範"))
        XCTAssertLessThan(dependency.lowerBound, requested.lowerBound)
        XCTAssertTrue(text.contains("## 読者への誠実さ"))
        XCTAssertTrue(text.contains("## 修正指示への使い方"))
        XCTAssertTrue(text.contains("originalは書き換えない"))
        XCTAssertTrue(text.hasSuffix("出力は指定のJSON配列のみ。"))
    }

    func testMissingSkillsFailInsteadOfSilentlyOmittingThem() throws {
        // Foundationのバンドルにはアプリの文章規範が含まれない。
        let unrelatedBundle = Bundle(for: NSObject.self)
        XCTAssertThrowsError(try TranslationWritingSkills.instructions(bundle: unrelatedBundle)) {
            XCTAssertEqual($0 as? GeminiError, .writingSkillLoadFailed)
        }
    }

    func testBothModesIncludeSkillsAndKeepGeminiPDFRequest() async throws {
        let service = GeminiService()
        for mode in TranslationMode.allCases {
            let body = try await service.buildRequestBody(
                base64PDF: "cGRm", mode: mode, pageNumber: 2, totalPages: 5
            )
            let encoded = try JSONSerialization.data(withJSONObject: body)
            let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            let contents = try XCTUnwrap(decoded["contents"] as? [[String: Any]])
            XCTAssertEqual(contents.count, 1)
            let parts = try XCTUnwrap(contents[0]["parts"] as? [[String: Any]])
            let pdf = try XCTUnwrap(parts[0]["inline_data"] as? [String: String])
            XCTAssertEqual(pdf["mime_type"], "application/pdf")
            XCTAssertEqual(pdf["data"], "cGRm")
            let prompt = try XCTUnwrap(parts[1]["text"] as? String)
            XCTAssertTrue(prompt.contains(try TranslationWritingSkills.instructions()))
            XCTAssertTrue(prompt.contains(mode == .knitting ? "棒針編み（knitting）" : "かぎ針編み（crochet）"))
            XCTAssertTrue(prompt.contains("2/5 ページ"))
            XCTAssertTrue(prompt.contains("k2tog"))
            XCTAssertTrue(prompt.contains("sc / single crochet"))
            XCTAssertTrue(prompt.contains("出力形式（JSON配列のみ）"))
        }
    }
}

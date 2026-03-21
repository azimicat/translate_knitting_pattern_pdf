import XCTest
@testable import KnittingTranslator

final class GeminiServiceTests: XCTestCase {

    private let service = GeminiService()

    // MARK: - parseResponse: 正常系

    func testParseResponse_validJSON() async throws {
        let data = makeResponse(text: #"[{"original":"Cast on 20 sts.","translation":"20目作り目する。"}]"#)
        let pairs = try await service.parseResponse(data: data)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].original,    "Cast on 20 sts.")
        XCTAssertEqual(pairs[0].translation, "20目作り目する。")
    }

    func testParseResponse_multiplePairs() async throws {
        let text = """
        [
          {"original":"Row 1: K2, P2","translation":"1段目：表2目、裏2目"},
          {"original":"Row 2: P2, K2","translation":"2段目：裏2目、表2目"}
        ]
        """
        let data = makeResponse(text: text)
        let pairs = try await service.parseResponse(data: data)
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[1].original, "Row 2: P2, K2")
    }

    func testParseResponse_withMarkdownFence() async throws {
        // Gemini が JSON を ```json ... ``` で囲む場合がある
        let text = "```json\n[{\"original\":\"K2, P2\",\"translation\":\"表2目、裏2目\"}]\n```"
        let data = makeResponse(text: text)
        let pairs = try await service.parseResponse(data: data)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].original, "K2, P2")
    }

    func testParseResponse_emptyPage() async throws {
        // テキストのないページは空配列 [] を返す
        let data = makeResponse(text: "[]")
        let pairs = try await service.parseResponse(data: data)
        XCTAssertTrue(pairs.isEmpty)
    }

    func testParseResponse_noArrayInText() async throws {
        // JSON 配列が存在しない場合も空配列を返す（クラッシュしない）
        let data = makeResponse(text: "このページにはテキストがありません。")
        let pairs = try await service.parseResponse(data: data)
        XCTAssertTrue(pairs.isEmpty)
    }

    // MARK: - parseResponse: 異常系

    func testParseResponse_emptyText_throws() async throws {
        let data = makeResponse(text: "")
        do {
            _ = try await service.parseResponse(data: data)
            XCTFail("emptyResponse エラーが投げられるべき")
        } catch let error as GeminiError {
            XCTAssertEqual(error, .emptyResponse)
        }
    }

    func testParseResponse_invalidJSON_returnsEmpty() async throws {
        // JSON として不正でもクラッシュせず空配列を返す
        let data = makeResponse(text: "[invalid json]")
        let pairs = try await service.parseResponse(data: data)
        XCTAssertTrue(pairs.isEmpty)
    }

    // MARK: - parseResponse: フィルタリング

    func testParseResponse_filtersWhitespaceOnlyOriginals() async throws {
        let text = """
        [
          {"original":"Row 1: K2","translation":"1段目：表2目"},
          {"original":"   ","translation":"空白のみ"},
          {"original":"Row 2: P2","translation":"2段目：裏2目"}
        ]
        """
        let data = makeResponse(text: text)
        let pairs = try await service.parseResponse(data: data)
        // 空白のみの original は除外される
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[0].original, "Row 1: K2")
        XCTAssertEqual(pairs[1].original, "Row 2: P2")
    }

    // MARK: - parseResponse: HTMLマークアップ保持

    func testParseResponse_preservesHTMLMarkup() async throws {
        // <b>/<i>/<u>/<h> タグがそのまま保持されること
        let text = """
        [
          {"original":"<h>Pattern Notes</h>","translation":"<h>パターンの注意事項</h>"},
          {"original":"<b>Row 1:</b> K2, P2","translation":"<b>1段目：</b>表2目、裏2目"},
          {"original":"<i>Note:</i> ssk tightly","translation":"<i>注意：</i>右上2目一度はきつめに"}
        ]
        """
        let data = makeResponse(text: text)
        let pairs = try await service.parseResponse(data: data)
        XCTAssertEqual(pairs.count, 3)
        XCTAssertEqual(pairs[0].original,    "<h>Pattern Notes</h>")
        XCTAssertEqual(pairs[0].translation, "<h>パターンの注意事項</h>")
        XCTAssertEqual(pairs[1].original,    "<b>Row 1:</b> K2, P2")
        XCTAssertEqual(pairs[1].translation, "<b>1段目：</b>表2目、裏2目")
    }

    // MARK: - parseResponse: 編み物用語の訳語

    func testParseResponse_knittingTerms_k2tog() async throws {
        // k2tog → 左上2目一度（「K2 目一度」などと訳されないこと）
        let text = """
        [{"original":"k2tog","translation":"左上2目一度"}]
        """
        let data = makeResponse(text: text)
        let pairs = try await service.parseResponse(data: data)
        XCTAssertEqual(pairs[0].translation, "左上2目一度")
    }

    func testParseResponse_knittingTerms_ssk() async throws {
        // ssk → 右上2目一度
        let text = """
        [{"original":"ssk","translation":"右上2目一度"}]
        """
        let data = makeResponse(text: text)
        let pairs = try await service.parseResponse(data: data)
        XCTAssertEqual(pairs[0].translation, "右上2目一度")
    }

    func testParseResponse_knittingTerms_sk2po_vs_s2kpo() async throws {
        // sk2po（右上3目一度）と s2kpo（中上3目一度）は別操作
        let text = """
        [
          {"original":"sk2po","translation":"右上3目一度"},
          {"original":"s2kpo","translation":"中上3目一度"}
        ]
        """
        let data = makeResponse(text: text)
        let pairs = try await service.parseResponse(data: data)
        XCTAssertEqual(pairs[0].translation, "右上3目一度")
        XCTAssertEqual(pairs[1].translation, "中上3目一度")
    }

    func testParseResponse_units_notTranslated() async throws {
        // mm, cm, g, oz などの単位は翻訳されずそのまま残ること
        let text = """
        [
          {"original":"Gauge: 20 sts = 10 cm","translation":"ゲージ：20目 = 10 cm"},
          {"original":"Needle: 3.5 mm","translation":"針：3.5 mm"},
          {"original":"Yarn: 100 g / 200 yd","translation":"糸：100 g / 200 yd"}
        ]
        """
        let data = makeResponse(text: text)
        let pairs = try await service.parseResponse(data: data)
        XCTAssertEqual(pairs.count, 3)
        // 単位がそのまま含まれていること
        XCTAssertTrue(pairs[0].translation.contains("cm"))
        XCTAssertTrue(pairs[1].translation.contains("mm"))
        XCTAssertTrue(pairs[2].translation.contains("g"))
        XCTAssertTrue(pairs[2].translation.contains("yd"))
        // 日本語化された単位が含まれないこと
        XCTAssertFalse(pairs[1].translation.contains("ミリメートル"))
        XCTAssertFalse(pairs[2].translation.contains("グラム"))
    }

    // MARK: - Helpers

    /// Gemini API レスポンス形式の JSON を Data として組み立てる
    private func makeResponse(text: String) -> Data {
        // 配列に包んでシリアライズし、ブラケットを除いて JSON 文字列値として使う
        let data    = try! JSONSerialization.data(withJSONObject: [text] as NSArray)
        let arrStr  = String(data: data, encoding: .utf8)!          // ["..."]
        let jsonVal = String(arrStr.dropFirst().dropLast())          // "..."（エスケープ済み）
        let json = """
        {"candidates":[{"content":{"parts":[{"text":\(jsonVal)}]}}]}
        """
        return json.data(using: .utf8)!
    }
}

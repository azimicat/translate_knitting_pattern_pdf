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

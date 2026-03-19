import XCTest
@testable import KnittingTranslator

final class TypstGeneratorTests: XCTestCase {

    private let gen = TypstGenerator()

    // MARK: - escapeTypst

    func testEscapeTypst_plainText() async {
        let result = await gen.escapeTypst("Hello, world!")
        XCTAssertEqual(result, "Hello, world!")
    }

    func testEscapeTypst_backslash() async {
        // バックスラッシュは最初にエスケープする（順序が重要）
        let result = await gen.escapeTypst("a\\b")
        XCTAssertEqual(result, "a\\\\b")
    }

    func testEscapeTypst_asterisk() async {
        // 編み物パターンで頻出: *K2, P2; rep from *
        let result = await gen.escapeTypst("*K2, P2; rep from *")
        XCTAssertEqual(result, "\\*K2, P2; rep from \\*")
    }

    func testEscapeTypst_hash() async {
        let result = await gen.escapeTypst("#MC yarn")
        XCTAssertEqual(result, "\\#MC yarn")
    }

    func testEscapeTypst_allSpecialChars() async {
        let result = await gen.escapeTypst("\\*_#@$`<>")
        XCTAssertEqual(result, "\\\\\\*\\_\\#\\@\\$\\`\\<\\>")
    }

    func testEscapeTypst_backslashProcessedFirst() async {
        // バックスラッシュを後から処理すると既にエスケープした \* が \\* になってしまう
        // 正しい実装では \ を最初に処理するため \* → \\* とならない
        let result = await gen.escapeTypst("\\*")
        XCTAssertEqual(result, "\\\\\\*")  // \ → \\ , * → \*
    }

    // MARK: - convertTags

    func testConvertTags_plainText() async {
        let result = await gen.convertTags("Cast on 20 sts.")
        XCTAssertEqual(result, "Cast on 20 sts.")
    }

    func testConvertTags_bold() async {
        let result = await gen.convertTags("<b>Row 1</b>: K2, P2")
        XCTAssertEqual(result, "#strong[Row 1]: K2, P2")
    }

    func testConvertTags_italic() async {
        let result = await gen.convertTags("<i>Note:</i> see pattern")
        XCTAssertEqual(result, "#emph[Note:] see pattern")
    }

    func testConvertTags_boldItalic() async {
        let result = await gen.convertTags("<b><i>Important</i></b>")
        XCTAssertEqual(result, "#strong[#emph[Important]]")
    }

    func testConvertTags_escapesSpecialCharsInsideTag() async {
        // タグ内のテキストも Typst エスケープされる
        let result = await gen.convertTags("<b>*K2*</b>")
        XCTAssertEqual(result, "#strong[\\*K2\\*]")
    }

    func testConvertTags_noTags() async {
        // タグなし → エスケープのみ適用
        let result = await gen.convertTags("*K2, P2*")
        XCTAssertEqual(result, "\\*K2, P2\\*")
    }

    func testConvertTags_emptyString() async {
        let result = await gen.convertTags("")
        XCTAssertEqual(result, "")
    }

    func testConvertTags_mixedContent() async {
        let result = await gen.convertTags("Use <b>MC</b> and <i>CC</i> yarn.")
        XCTAssertEqual(result, "Use #strong[MC] and #emph[CC] yarn.")
    }
}

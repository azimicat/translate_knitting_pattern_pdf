import XCTest
@testable import KnittingTranslator

final class TranslationModeTests: XCTestCase {

    func testRawValues() {
        XCTAssertEqual(TranslationMode.knitting.rawValue, "棒針")
        XCTAssertEqual(TranslationMode.crochet.rawValue,  "かぎ針")
    }

    func testAllCasesCount() {
        XCTAssertEqual(TranslationMode.allCases.count, 2)
    }

    func testIdentifiable_idEqualsRawValue() {
        XCTAssertEqual(TranslationMode.knitting.id, "棒針")
        XCTAssertEqual(TranslationMode.crochet.id,  "かぎ針")
    }
}

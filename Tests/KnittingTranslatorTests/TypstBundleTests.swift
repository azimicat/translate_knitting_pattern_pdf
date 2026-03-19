import XCTest
@testable import KnittingTranslator

final class TypstBundleTests: XCTestCase {

    private func makeGenerator() -> TypstGenerator { TypstGenerator() }

    func testFindTypst_returnsExecutablePath() async throws {
        let gen = makeGenerator()
        let path = try await gen.findTypst()
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: path),
            "findTypst() が返したパス \(path) は実行可能ファイルではありません"
        )
    }

    func testFindTypst_cachedPath_sameOnSecondCall() async throws {
        let gen = makeGenerator()
        let path1 = try await gen.findTypst()
        let path2 = try await gen.findTypst()
        XCTAssertEqual(path1, path2, "2回目の呼び出しで異なるパスが返されました")
    }

    func testFindTypst_cachedBinary_notReCopied() async throws {
        let gen = makeGenerator()
        _ = try await gen.findTypst()   // 1回目: コピーが発生する
        let path = try await gen.findTypst()    // 2回目: キャッシュを使う

        let mod1 = try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date

        _ = try await gen.findTypst()   // 3回目: 更新日時が変わらないはず
        let mod2 = try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date

        XCTAssertEqual(mod1, mod2, "キャッシュ済みのバイナリが不必要に再コピーされました")
    }
}

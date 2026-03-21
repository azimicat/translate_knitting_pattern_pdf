import Foundation
import PDFKit

// MARK: - Types

/// 翻訳の1ペア（原文 + 日本語訳）。pageIndex は JSON に含まれず translatePage() で付与する。
struct TranslationPair: Decodable {
    let original: String
    let translation: String
    var pageIndex: Int = 0

    private enum CodingKeys: String, CodingKey {
        case original, translation
    }
}

enum GeminiError: LocalizedError, Equatable {
    case pdfLoadFailed
    case apiError(statusCode: Int, body: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .pdfLoadFailed:
            return "PDFの読み込みに失敗しました"
        case .apiError(let code, let body):
            return "Gemini API エラー (HTTP \(code)): \(body)"
        case .emptyResponse:
            return "Gemini API からの応答が空です"
        }
    }
}

// MARK: - GeminiService

actor GeminiService {

    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

    /// 翻訳は1ページあたり最大300秒かかる場合があるためタイムアウトを長めに設定
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 300
        config.timeoutIntervalForResource = 1800
        return URLSession(configuration: config)
    }()

    init() {}

    // MARK: - Public

    /// PDF を1ページずつ Gemini に送り、テキスト抽出と英→日翻訳を一括で行う。
    /// - Parameters:
    ///   - url: 翻訳対象のPDF URL（security-scoped resource は呼び出し元が開くこと）
    ///   - mode: 棒針 / かぎ針（プロンプトの文脈として使用）
    ///   - apiKey: Google AI Studio の API キー
    ///   - progressCallback: 0.0〜1.0 の進捗を受け取るクロージャ
    func translatePDF(
        at url: URL,
        mode: TranslationMode,
        apiKey: String,
        progressCallback: ((Double) async -> Void)? = nil
    ) async throws -> [TranslationPair] {

        guard let document = PDFDocument(url: url) else {
            throw GeminiError.pdfLoadFailed
        }

        let pageCount = document.pageCount
        guard pageCount > 0 else { return [] }

        var allPairs: [TranslationPair] = []

        for pageIndex in 0..<pageCount {
            try Task.checkCancellation()

            guard let page = document.page(at: pageIndex) else { continue }

            // 1ページずつ PDF に再構築して送信（ページ単位で進捗更新するため）
            let singlePageDoc = PDFDocument()
            singlePageDoc.insert(page, at: 0)
            guard let pageData = singlePageDoc.dataRepresentation() else { continue }

            let pairs = try await translatePage(
                pageData: pageData,
                pageNumber: pageIndex + 1,
                totalPages: pageCount,
                mode: mode,
                apiKey: apiKey
            )
            allPairs.append(contentsOf: pairs)

            await progressCallback?(Double(pageIndex + 1) / Double(pageCount))
        }

        return allPairs
    }

    // MARK: - Private: Network

    private func translatePage(
        pageData: Data,
        pageNumber: Int,
        totalPages: Int,
        mode: TranslationMode,
        apiKey: String
    ) async throws -> [TranslationPair] {

        let body = buildRequestBody(
            base64PDF: pageData.base64EncodedString(),
            mode: mode,
            pageNumber: pageNumber,
            totalPages: totalPages
        )

        var urlComponents = URLComponents(string: endpoint)!
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? "(no body)"
            throw GeminiError.apiError(statusCode: http.statusCode, body: bodyText)
        }

        var pairs = try parseResponse(data: data)
        // pageIndex は JSON に含まれないため、ここで注入する
        for i in pairs.indices { pairs[i].pageIndex = pageNumber - 1 }
        return pairs
    }

    // MARK: - Private: Request builder

    /// Gemini へ送信するリクエストボディを構築する。
    /// プロンプトはテキスト種別（パターン指示 vs 説明文）で段落化ルールを変え、
    /// <b>/<i> タグでフォントスタイルを保持し、ヘッダー/フッター・空行を除外するよう指示する。
    /// thinking モードは翻訳タスクでは不要かつ大幅な遅延原因になるため無効化する。
    private func buildRequestBody(
        base64PDF: String,
        mode: TranslationMode,
        pageNumber: Int,
        totalPages: Int
    ) -> [String: Any] {
        let modeDesc = mode == .knitting ? "棒針編み（knitting）" : "かぎ針編み（crochet）"
        let prompt = """
        このPDFは\(modeDesc)パターンの \(pageNumber)/\(totalPages) ページです。
        本文テキストを英語から日本語へ翻訳してください。

        テキストの種類によってグループ化のルールを変えてください：

        【パターン部分（編み方の指示）】
        例: "Row 1: K2, P2, *K4; rep from *", "Round 3: sc in each st"
        → 1文（1つの編み指示、または意味のひとまとまり）ごとに1要素にする
        → 途中で改行されていても同一の指示なら1要素にまとめる

        【パターン以外の部分（説明文・材料・注意書きなど）】
        例: 素材の説明、ゲージ情報、完成サイズ、作り方の注意
        → 意味のまとまり（段落・ブロック）ごとに1要素にする
        → 複数行でも同じ段落・話題であれば1要素にまとめる

        フォントスタイルの保持：
        - 太字の部分は <b>テキスト</b> で囲む
        - 斜体の部分は <i>テキスト</i> で囲む
        - 下線の部分は <u>テキスト</u> で囲む
        - セクション名・章タイトル（見出し）は <h>テキスト</h> で囲む
        - original と translation の両方に同じスタイルマークアップを適用する
        - 上記以外の HTML タグは使わないこと

        編み物用語の訳語（必ずこの対応を使うこと）：

        【基本ステッチ】
        - k / knit → 表編み
        - p / purl → 裏編み
        - st / sts → 目
        - St st / stockinette stitch / stocking stitch → メリヤス編み

        【増減目（棒針）】
        - k2tog → 左上2目一度
        - k2tog tbl / knit two together through back loop → 表編みのねじり2目一度
        - k3tog → 左上3目一度
        - ssk → 右上2目一度
        - sssk → 左上3目一度
        - sssp → 裏目の右上2目一度
        - ssp → 裏目の右上2目一度
        - p2tog → 裏目の左上2目一度
        - p2tog tbl → 裏目のねじり2目一度（裏目の右上2目一度）
        - p3tog → 裏目の左上3目一度
        - SKP / skpo / skp / sl 1 k1 psso → 右上2目一度
        - sk2p / sk2po / sk2togpo → 右上3目一度（1目すべって2目一度に編み、すべった目をかぶせる）
        - s2kp / s2kpo / s2togkpo / cdd → 中上3目一度（2目一緒にすべって1目編み、すべった2目をかぶせる）
        - inc(s) / increase(s) → 増し目
        - inc('d) → 増やす、増やした
        - dec → 減らし目
        - M1R / make 1 right leaning stitch → ねじり増し目（右にねじる）
        - M1L / make 1 left leaning stitch → ねじり増し目（左にねじる）
        - m1 / make 1 stitch → ねじり増し目
        - m1 k-st / make 1 knit stitch → 表目のねじり増し目
        - m1 p-st / make 1 purl stitch → 裏目のねじり増し目
        - raised increase → ねじり増し目
        - lifted increase → 1段下の目を引き上げて増し目する方法
        - RLI / right lifted increase → 右増し目
        - RLPI / right lifted purl increase → 裏目の右増し目
        - LLI / left lifted increase → 左増し目
        - LLPI / left lifted purl increase → 裏目の左増し目
        - kfb / k1fb / k1f&b / knit into front and back → 表目の編み出し増し目（1目から2目、bar increase）
        - kfbf / knit into front back and front → 3目の編み出し増し目
        - kfpb / knit into front then purl into back → 表裏組み合わせ編み出し増し目（1目から2目）
        - pfb / p1f&b / purl into front and back → 裏目の編み出し増し目（1目から2目）
        - pfkb / purl into front then knit into back → 裏表組み合わせ編み出し増し目（1目から2目）
        - pb / p1b / p-b / purl into stitch in row below → 前段の目に裏目を編む

        【かけ目・ねじり目】
        - yo / yarn over → かけ目
        - yo2 / yarn over twice / double yarn over → かけ目を2回する
        - yf / yarn forward → かけ目
        - yfrn / yarn forward round needle → かけ目
        - yon / yarn over needle → かけ目
        - yrn / yarn around needle → かけ目
        - k tbl / k1 tbl / knit through back loop → 表目のねじり目
        - p tbl → 裏目のねじり目
        - tbl / through the back of loop → ループの後ろから
        - elongated stitch / k1 wrapping yarn twice around needle → ドライブ編み（引き伸ばし目）

        【すべり目】
        - sl / slip → すべり目
        - sl 1k / sl1k / sl 1 knitwise → 表目のようにすべり目
        - sl 1p / sl1p / sl 1 purlwise → 裏目のようにすべり目
        - sl wyib → 糸を後ろに置いてすべり目
        - sl wyif → 糸を手前に置いてすべり目
        - wyb / wyib / with yarn in back → 糸を後ろ側に置いて
        - wyf / wyif / with yarn in front → 糸を手前に置いて

        【段・ラウンド・方向】
        - row(s) → 段
        - rnd(s) → ラウンド
        - eor / end of row / end of round → 段の終わり
        - RS / right side → 表面
        - WS / wrong side → 裏面
        - RS facing / right side facing → 表面が見えるように（外表にして）
        - WS facing / wrong side facing → 裏側が見えるようにして（中表にして）
        - inside out → 中表
        - LH / left-hand → 左側
        - LN / left needle → 左の針
        - RH / right-hand → 右側
        - RN / right needle → 右針
        - bottom up → 裾から上に向かって編む
        - top down → 上から下に向かって編む（ネックから編む）
        - toe-up → つま先から編む（靴下の編み方向）
        - clockwise → 時計回りに
        - counter clockwise → 反時計回りに
        - across → 〜を渡って、〜の全体に及んで
        - beg / begin / beginning → 始め、編み始め
        - rem / remain(s) / remaining → 残り、残りの
        - prev / previous → 前の
        - opp / opposite → 反対側の
        - alt / alternate / alternately → 交互に、一つおきに
        - every → 〜ごとに
        - every other → 1つ置きに
        - evenly → 均等に
        - one at a time → ひとつずつ
        - bet / between → 間
        - cont / continue(s) / continuing → 続けて〜、〜を続ける
        - foll / follow(s) / following → 続けて〜、〜のように
        - est / established → 確立したパターンに従って
        - flat → 平ら（往復編み）
        - incl / including / inclusive → ～を含む
        - approx / approximately → 約、おおよそ

        【作り目・伏せ止め】
        - co / cast on → 作り目、編み始め
        - bo / BO / bind off / cast off → 目を止める、伏せ止め
        - bound off → 目を止めた〜（bind offの過去形）
        - bor / beginning of row/round → 段のはじめ
        - provisional cast on / chained provisional cast on → 別鎖の作り目
        - provisional crochet chain cast on → 別鎖の作り目
        - cable cast on → 編みながら作る作り目
        - knitted cast on → 編みながら作る作り目
        - long tail cast on → 指でかける作り目
        - backward loop cast on → 巻き増し目（作り目）
        - three-needle bind off → 引き返し縫い

        【マーカー・目数リング】
        - pm / place marker → マーカーをつける
        - sm / slm / slip marker → マーカーを移す
        - stitch holder → 目止め

        【くり返し記号】
        - rep → 繰り返す
        - * ~ * または * ~ ; = アスタリスク間の操作を繰り返す
        - ( ) = 括弧内の操作を1セットとして繰り返す
        - [ ] = 括弧内の操作をくり返す
        - repeat ~ times = あと〜回くり返す
        - once = 1回、twice = 2回、three times = 3回
        - every row = 毎段くり返す
        - every other row = 1段おきに
        - every XX rows = XX段ごとに
        - mult / multiple → 倍数

        【その他の操作】
        - psso / pass slipped stitch(es) over → 目をかぶせる
        - W&T / w&t / wt / wrap and turn → ラップ&ターン（引き返し編みの手法）
        - short rows → 引き返し編み
        - drop → （目を）落とす
        - pwise / purlwise → 裏目を編むように
        - kwise / knitwise → 表編みを編むように
        - pu / puk / pick up / pick up and knit → 拾い目をする
        - pick up → （落とした目を）拾う
        - patt(s) / pattern(s) → 模様
        - working yarn → 編むのに使用している糸
        - rm / remove marker → マーカーを外す
        - fasten off → 糸を止める
        - finishing → 仕上げ
        - blocking / block → ブロッキング（水通しまたはスチームで編み目を整える仕上げ工程）
        - desired length → 好みの長さ
        - jog → 段差（輪編みで色替えをした時の段差）
        - jogless → 段差をなくす工夫
        - inst / instructions → 指示
        - direction(s) → 方向、指示
        - diameter → 直径
        - circumference → 周囲

        【編み地・技法の種類】
        - St st / stockinette stitch / stocking stitch → メリヤス編み
        - rev St st / reverse stockinette stitch → 逆メリヤス編み（裏メリヤス）
        - g st / garter stitch → ガーター編み
        - seed stitch → かのこ編み
        - moss stitch → かのこ編み
        - rib / ribbing → リブ編み（ゴム編み）
        - k1, p1 ribbing / 1x1 ribbing → 1目ゴム編み
        - k2, p2 ribbing / 2x2 ribbing → 2目ゴム編み
        - ridge → ガーター模様（ガーター編み2段で1リッジ）
        - cable(s) / cab → 交差模様、なわ編み
        - Intarsia → 縦糸渡しの編み込み
        - Fair Isle knitting → フェア アイル編み（シェットランドの伝統的な編み込み）
        - stranded knitting → 糸を渡しながらの編み込み
        - eyelet → 透かし目（穴）
        - duplicate stitch → メリヤス刺繍
        - Entrelac → エントレラック編み
        - kitchener stitch / grafting → メリヤスはぎ（はぎ合わせの技法）
        - mattress stitch → すくいとじ
        - back stitch seam → 半返し縫い
        - seaming → とじはぎ
        - seamless → 縫い目がない（輪に編む仕立て）
        - vertical seaming → 段と段のとじ
        - i-cord → 丸コード（輪で編むひも状の編み地）
        - nupp → ヌープ（玉編みの技法）
        - MB / make bobble → ボブル（玉編み）を作る
        - mitered square knitting → ドミノ編み
        - k1b / k1-b / k-b / knit one stitch in row below → 前段の目に針を入れて表編みをする
        - pb / p1b / p-b → 前段の目に裏目を編む
        - float(s) → 渡り糸
        - pleat → プリーツ
        - ruffle → フリル
        - shoulder shaping → 肩のシェイピング
        - armhole shaping → 袖ぐりのシェイピング
        - waist shaping → ウェストシェイピング
        - sideways → 横向きに編む
        - schematic → 図面（製図）
        - allover → 総模様
        - facing → 見返し
        - chart → 編み図、図表

        【採寸・サイズ用語】
        - Chest / Bust → 胸囲
        - Center back neck to wrist → 裄丈
        - Center back neck to waist → 背丈
        - Cross Back → 背肩幅
        - Sleeve Length → 袖丈
        - Upper Arm → 腕回り
        - Armhole Depth → 腕付け回り
        - Waist → 胴囲（ウエスト）
        - Hip → 腰囲
        - Head → 頭回り
        - ease → ゆとり（着丈ゆるみ）
        - elasticity → 伸縮性
        - gusset → まち（靴下・ミトン等）
        - in / inch → インチ（単位はそのまま "in" または "inch" と表記）
        - cm / centimeter(s) → cm（単位はそのまま "cm" と表記）
        - m / meter(s) → m（単位はそのまま "m" と表記）

        【道具・素材】
        - spn / single pointed needle → 玉付き棒針
        - dpn(s) / double pointed needle(s) → 両端が尖った針（4本針または5本針）
        - circ(s) / circular(s) / circular needle(s) → 輪針
        - interchangeable circular needles → 針先が取り替え可能な輪針
        - cn / cable needle → なわ編針
        - needle cap → 棒針用のキャップ
        - holder → ほつれ止め
        - tapestry needle / darning needle → とじ針
        - swift → かせ巻き器
        - ball winder → 玉巻器
        - swatch → ゲージを測るための試し編み
        - gauge / tension → ゲージ
        - notions → 編み道具一式
        - WPI / wraps per inch → WPI（1インチの巻き数）
        - mm / millimeter(s) → mm（単位はそのまま表記）
        - yd(s) / yard(s) → yd（単位はそのまま表記）
        - oz / ounce(s) → oz（単位はそのまま表記）
        - g / gram(s) → g（単位はそのまま表記）
        - yardage → 糸長
        - skein → かせ（糸の巻き形状）
        - hank → （毛糸の）1かせ
        - ball → 毛糸玉
        - ply → 糸の撚り（本数）
        - heathered yarn → 杢糸（異色の糸を2本以上より合わせた糸）
        - variegated yarn → 段染め糸
        - double yarn / held together → 糸を2本どりにして
        - waste yarn / scrap yarn → 別糸
        - MC / main color → 地色
        - CC / contrasting color → 配色
        - lifeline → ライフライン（編み地に通しておく安全の糸）
        - live stitch(es) → 止めていない状態の編み目
        - pom pom → ポンポン
        - sleeve cap → 袖山
        - stash → ストック糸
        - positive ease → プラスのゆるみ
        - negative ease → マイナスのゆるみ（寸法を減らす）
        - strand(s) → 糸の本数
        - selvage / selvedge / se → セルベッジ（端目）
        - lys / local yarn store → 最寄りの毛糸店
        - drapey / drape → ドレープ感のある
        - English knitting → アメリカ式（の編み方）
        - Continental knitting → フランス式（の編み方）
        - bar → 目と目の間に渡っている糸（シンカーループ）
        - bl / back loop → 針にかかっている目の後ろ側
        - fl / front loop(s) → 針にかかっている目の手前側
        - double left-slanting decrease → 右上3目一度（= sssk）
        - double right-slanting decrease → 左上3目一度（= k3tog）
        - double vertical decrease → 中上3目一度（= cdd）
        - dbl dec / double decrease → 3目一度の総称
        - dec('d) / decreasing / decreased → 減らす、減らした

        【糸の太さ（CYCA分類）】
        - lace / cobweb / lace weight → レース糸・極細（CYCA 0）
        - fingering / sock → 合細・中細（CYCA 1）
        - sport / baby → 合太・Fine（CYCA 2）
        - DK / light worsted → 合太・並太（CYCA 3）
        - worsted / aran / afgan → 並太（CYCA 4）
        - bulky / chunky / craft / rug → 極太・超極太（CYCA 5）
        - super bulky / roving / super chunky → 超極太（CYCA 6）

        【かぎ針編み基本ステッチ】
        - sc / single crochet → 細編み
        - hdc / half double crochet → 中長編み
        - dc / double crochet → 長編み
        - tr / treble crochet / triple crochet → 長々編み
        - tr tr / triple treble crochet → 長々々編み
        - dtc / dtr / double triple crochet / double treble crochet → 長々々編み
        - htr / half treble crochet → 中長編み
        - sl st / ss / slip stitch → 引き抜き編み
        - ch / chain → 鎖編み
        - rev sc / reverse single crochet → 逆細編み（バック細編み）
        - fsc / foundation single crochet → 細編みの作り目
        - fdc / foundation double crochet → 長編みの作り目
        - fc / foundation chain → 鎖の作り目

        【かぎ針編み増減目】
        - sc2tog → 細編みの2目一度
        - sc3tog → 細編みの3目一度
        - hdc2tog → 中長編みの2目一度
        - hdc3tog → 中長編みの3目一度
        - htr2tog → 中長編みの2目一度
        - htr3tog → 中長編みの3目一度
        - dc2tog → 長編みの2目一度
        - dc3tog → 長編みの3目一度
        - tr2tog → 長々編みの2目一度
        - tr3tog → 長々編みの3目一度

        【かぎ針編み引き上げ編み】
        - fpdc / front post double crochet → 長編みの表引き上げ編み
        - fpdc2tog → 長編み表引き上げ編みの2目一度
        - fptr / front post treble crochet → 長々編み表引き上げ編み
        - fptr2tog → 長々編み表引き上げ編みの2目一度
        - fptc2tog → 長々編み表引き上げ編みの2目一度
        - flo / front loop only → 表目の半目のみに入れて編む
        - blo / back loop only → 向こう側の半目のみに入れて編む
        - bpdc / back post double crochet → 長編みの裏引き上げ編み
        - bphdc / back post half double crochet → 中長編みの裏引き上げ編み
        - bphtr / back post half treble crochet → 中長編みの裏引き上げ編み
        - bptr / back post treble crochet → 長々編みの裏引き上げ編み

        【かぎ針編みその他】
        - hook / crochet hook → かぎ針
        - tch / turning chain → 立ち上りの鎖目
        - ch st / chain stitch → 鎖目
        - sp(s) / space / spaces → スペース（チェーン間の空間）
        - yo / yoh / yarn over / yarn over hook → 糸をかける
        - draw through → 引き抜く
        - cluster / cluster stitch / cs → 玉編み（複数目を一度に引き抜く技法）
        - pc / pop / popcorn → ポップコーン編み
        - picot → ピコット
        - post → 柱（編み目の柱の部分）
        - sk / skip → 目を飛ばす
        - miss → 目を飛ばす
        - join → つなぐ
        - join as you go → 編みつなぎながら進める
        - lp(s) / loop(s) → ループ
        - slipknot → 編み始めのループ
        - slip stitch seam → 引き抜きとじ

        【棒針編み追加用語】
        - tog / together → 一緒に、一度に
        - toe-up → つま先から編む（靴下の編み方向）
        - top down → 上から下に向かって編む（ネックから編む）
        - trn / turn → ひっくり返す、方向を変える
        - twist(ed) → ねじる、ねじれた
        - unravel → （糸を）ほどく
        - variegated yarn → 段染め糸
        - vertical seaming → 段と段のとじ
        - waist shaping → ウェストシェイピング（増減目）
        - waste yarn / scrap yarn → 別糸
        - work even / work straight → 増減なしで真っ直ぐに編み進む
        - work flat / work back and forth → 平編み（往復編み）
        - work in the round / circular knitting → 輪に編む
        - working needle → 編むのに使用している針
        - tight → きつい、きつめ

        共通ルール：
        - ページ番号・ヘッダー・フッターは除外する
        - 空行は除外する
        - このページにテキストがない場合は空配列 [] を返す
        - 他の文言は一切出力せず、JSON配列だけを返すこと
        - 単位（mm、cm、m、in、inch、yd、oz、g、WPI など）は翻訳せずそのまま表記すること

        出力形式（JSON配列のみ）:
        [{"original": "英語の<b>原文</b>", "translation": "日本語の<b>訳</b>"}, ...]
        """

        return [
            "contents": [
                [
                    "parts": [
                        ["inline_data": ["mime_type": "application/pdf", "data": base64PDF]],
                        ["text": prompt],
                    ]
                ]
            ],
            "generationConfig": [
                "thinkingConfig": ["thinkingBudget": 0]
            ],
        ]
    }

    // MARK: - Internal: Response parser (internal for testing)

    /// Gemini のレスポンス JSON から TranslationPair 配列を抽出する。
    /// Gemini は JSON の前後に markdown コードフェンスや余分な文言を付加することがあるため、
    /// 最初の `[` から最後の `]` までを切り出してデコードする。
    func parseResponse(data: Data) throws -> [TranslationPair] {
        struct GeminiResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String? }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let text = decoded.candidates.first?.content.parts.first?.text,
              !text.isEmpty else {
            throw GeminiError.emptyResponse
        }

        // JSON配列部分を抽出（テキストなしページは [] を返す）
        guard let start = text.firstIndex(of: "["),
              let end   = text.lastIndex(of: "]") else {
            return []
        }

        guard let jsonData = String(text[start...end]).data(using: .utf8),
              let pairs = try? JSONDecoder().decode([TranslationPair].self, from: jsonData) else {
            return []
        }

        // 原文が空白のみのペアを除外（Gemini が稀に空エントリを含めることがある）
        return pairs.filter { !$0.original.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

/// 翻訳対象の編み物ジャンル
enum TranslationMode: String, CaseIterable, Identifiable {
    case knitting = "棒針"
    case crochet  = "かぎ針"

    var id: String { rawValue }
}

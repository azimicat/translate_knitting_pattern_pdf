enum TranslationMode: String, CaseIterable, Identifiable {
    case knitting = "棒針"
    case crochet  = "かぎ針"

    var id: String { rawValue }

    var dictionaryFileName: String {
        switch self {
        case .knitting: return "needle_dictionary"
        case .crochet:  return "crochet_dictionary"
        }
    }
}

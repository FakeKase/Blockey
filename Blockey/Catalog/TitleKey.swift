import Foundation

/// The key two titles are compared by. For matching and grouping only: what the user sees is
/// always a real spelling they typed. See ADR 006, "Normalisation".
enum TitleKey {

    private static let zeroWidthToDrop: Set<Unicode.Scalar> = ["\u{200B}", "\u{FEFF}"]

    /// In order: remove U+200B and U+FEFF (but not U+200D, which glues emoji sequences
    /// together), NFKC, fold case and width with no locale, then collapse whitespace and trim.
    ///
    /// NFKC rather than NFC because Thai SARA AM can be one scalar (U+0E33) or two
    /// (U+0E4D U+0E32), and only compatibility normalisation makes those one key. It also does
    /// the width folding for full-width Latin and half-width katakana.
    ///
    /// Deliberately NO `.diacriticInsensitive`: it strips Thai tone marks and vowels, so
    /// ข้าว (rice) would equal ขาว (white). No fuzzy merging either.
    ///
    /// Whitespace is collapsed after NFKC rather than before, because compatibility mapping can
    /// itself produce whitespace (U+3000 becomes a plain space), and the order is otherwise
    /// unobservable.
    static func normalize(_ title: String) -> String {
        var scalars = String.UnicodeScalarView()
        for s in title.unicodeScalars where !zeroWidthToDrop.contains(s) { scalars.append(s) }

        let folded = String(scalars)
            .precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)

        return folded
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

import Foundation

/// What a title becomes when the inbox composer submits it. Pure, so the rules are tested.
enum ComposerTitle {

    static let maxLength = 200

    /// Pasted newlines become spaces (a chip must be one line), the result is trimmed, and it is
    /// capped at 200 characters. The cap counts `Character`s, so it never cuts inside a Thai
    /// cluster or an emoji, and is trimmed again so a cut after a space leaves no trailing blank.
    static func forSubmit(_ raw: String) -> String {
        var out = String.UnicodeScalarView()
        var previousWasCR = false
        for s in raw.unicodeScalars {
            switch s {
            case "\n" where previousWasCR:
                previousWasCR = false      // the LF of a CRLF pair: already one space
            case "\n", "\r", "\u{0085}", "\u{2028}", "\u{2029}":
                out.append(" ")
                previousWasCR = (s == "\r")
            default:
                out.append(s)
                previousWasCR = false
            }
        }
        let trimmed = String(out).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

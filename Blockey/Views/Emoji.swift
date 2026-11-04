import CoreText
import SwiftUI
import UIKit

/// Emoji, with a symbol to fall back on where the platform cannot draw them.
///
/// The iOS simulator runtime ships no usable emoji font — only
/// `AppleColorEmoji-160px.ttc` tucked under `CoreAddition`, which the text
/// system does not fall back to — so on the simulator every emoji comes out as
/// a missing-glyph box at every size. Real devices are fine.
///
/// That would be someone else's problem except that it makes the simulator
/// useless for checking the timeline, and a screenshot that lies is worse than
/// no screenshot. So rather than assume, the app asks the font system what it
/// can actually draw and uses an SF Symbol wherever the answer is "not this".
enum Emoji {

    /// Whether emoji render on this device at all. Resolved once.
    ///
    /// Neither of the obvious tests works. The simulator's stunted emoji font
    /// *is* installed and *does* contain the glyph, and CoreText even picks it
    /// — `.AppleColorEmojiUI` comes back from font cascade — it then fails at
    /// draw time, because the only strike present is a 160px one nothing asks
    /// for. So the question has to be asked the only way that cannot be fooled:
    /// draw an emoji, draw a character that is guaranteed to have no glyph
    /// anywhere, and see whether the two came out the same. Identical means
    /// both drew the missing-glyph box, and there are no emoji on this system.
    static let isSupported: Bool = {
        let emoji = rendering(of: "\u{1F9E0}")
        let definitelyMissing = rendering(of: "\u{10FFFF}")
        return !emoji.isEmpty && emoji != definitelyMissing
    }()

    /// One character, drawn into a small bitmap. The pixels are the answer.
    private static func rendering(of text: String) -> [UInt8] {
        let side = 28
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress,
                                          width: side,
                                          height: side,
                                          bitsPerComponent: 8,
                                          bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            let attributed = NSAttributedString(string: text,
                                                attributes: [.font: UIFont.systemFont(ofSize: 20)])
            context.textPosition = CGPoint(x: 2, y: 5)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        return pixels
    }

    /// `"🧠  Deep work"`, degrading to `"Deep work"`.
    static func prefixed(_ emoji: String, _ text: String) -> String {
        isSupported ? "\(emoji)  \(text)" : text
    }
}

/// A category's face: its emoji, or its symbol where emoji are unavailable.
struct CategoryGlyph: View {
    let style: CategoryStyle
    var size: Font = .callout
    /// Symbols carry no colour of their own, so they take the category tint.
    /// Emoji bring their own and are left alone.
    var tinted: Bool = true

    var body: some View {
        if Emoji.isSupported {
            Text(style.emoji)
                .font(size)
        } else {
            Image(systemName: style.symbolName)
                .font(size)
                .foregroundStyle(tinted ? AnyShapeStyle(style.spine) : AnyShapeStyle(.primary))
        }
    }
}

/// A standalone emoji used as illustration — the large glyph above an empty
/// state — with a light-weight symbol standing in when emoji are unavailable.
struct EmojiIllustration: View {
    let emoji: String
    let symbolName: String
    var size: CGFloat = 38

    var body: some View {
        if Emoji.isSupported {
            Text(emoji)
                .font(.system(size: size))
        } else {
            Image(systemName: symbolName)
                .font(.system(size: size * 0.9, weight: .light))
                .foregroundStyle(.tertiary)
        }
    }
}

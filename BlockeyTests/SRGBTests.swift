import Testing
import Foundation
@testable import Blockey

/// Plan Appendix A.4b, SRGB hex. The grammar is the one stored in backups, so it is strict.
@Suite("SRGB hex")
struct SRGBTests {

    @Test func hexParsesUppercaseAndLowercase() {
        #expect(SRGB(hex: "#4664DC")?.hex == "#4664DC")
        #expect(SRGB(hex: "#4664dc")?.hex == "#4664DC")
        #expect(SRGB(hex: "#aBcDeF")?.hex == "#ABCDEF")
    }

    @Test(arguments: ["", "#", "#FFF", "#FFFFF", "#FFFFFFF", "#FFFFFFFF", "FFFFFF", "##FFFFF",
                      " #FFFFFF", "#FFFFFF ", "#FFFFFF\n", "#GGGGGG", "#12345G", "0xFFFFFF",
                      "#ＦＦＦＦＦＦ", "#٠٠٠٠٠٠", "rgb(1,2,3)"])
    func hexRejectsShortLongAlphaMissingHashWhitespaceAndJunk(_ text: String) {
        #expect(SRGB(hex: text) == nil)
    }

    @Test func hexWriterEmitsCanonicalUppercase() {
        #expect(SRGB(r: 0.5, g: 1, b: 0).hex == "#80FF00")
        #expect(SRGB.black.hex == "#000000")
        #expect(SRGB.white.hex == "#FFFFFF")
    }

    @Test func hexRoundTripsThroughEightBitSRGB() {
        // Every byte value on every channel, not a sample.
        for v in 0...255 {
            let hex = String(format: "#%02X%02X%02X", v, 255 - v, (v * 7) % 256)
            #expect(SRGB(hex: hex)?.hex == hex)
        }
    }

    @Test func writerClampsOutOfRangeAndNonFiniteChannels() {
        #expect(SRGB(r: -1, g: 2, b: .nan).hex == "#00FF00")
        #expect(SRGB(r: .infinity, g: 0, b: 0).hex == "#000000")
    }

    @Test func writerSurvivesChannelsTooLargeForAnInt() {
        // Finite, but v * 255 overflows Int (or Double); the writer must clamp, not trap.
        #expect(SRGB(r: 1e300, g: -1e300, b: Double.greatestFiniteMagnitude).hex == "#FF00FF")
        #expect(SRGB(r: -Double.greatestFiniteMagnitude, g: 1e19, b: 0.5).hex == "#00FF80")
    }

    @Test func rgbLiteralMatchesHex() {
        #expect(SRGB(rgb: 0x4664DC) == SRGB(hex: "#4664DC"))
    }

    @Test func hexAgreesWithTheCatalogsCanonicalGrammar() {
        // Two parsers for one stored format must accept exactly the same strings.
        let samples = ["#4664dc", "#4664DC", "4664DC", "#FFF", "#4664DCFF", " #4664DC", "#GGGGGG", "#4664D"]
        for s in samples {
            #expect((SRGB(hex: s) != nil) == (CategoryCatalog.canonicalHex(s) != nil), "\(s)")
        }
    }
}

import Testing
import Foundation
@testable import Blockey

/// Reading the expiry date out of a `.mobileprovision` blob.
///
/// The real file is a CMS signature wrapped around an XML property list, so the
/// parser has to find the plist inside a wrapper of arbitrary binary. These
/// build that shape synthetically — binary noise on both sides of a real plist —
/// because the genuine article is only present in a signed device build.
@Suite("Provisioning profile")
struct ProvisioningProfileTests {

    private func blob(plist: String,
                      prefix: [UInt8] = [0x30, 0x82, 0x0A, 0x00, 0xFF, 0x00],
                      suffix: [UInt8] = [0x00, 0xAB, 0xCD]) -> Data {
        var data = Data(prefix)
        data.append(Data(plist.utf8))
        data.append(Data(suffix))
        return data
    }

    private let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <plist version="1.0">
    <dict>
        <key>Name</key>
        <string>iOS Team Provisioning Profile: com.kase.blockey</string>
        <key>ExpirationDate</key>
        <date>2026-09-25T06:32:29Z</date>
    </dict>
    </plist>
    """

    @Test("Finds the expiry inside a signed wrapper")
    func parsesExpiry() throws {
        let found = try #require(ProvisioningProfile.expirationDate(in: blob(plist: plist)))

        // Gregorian on purpose, and the only literal year left in the tests (issue #6): it is the
        // fixture's own ISO-8601 text above, parsed to an absolute instant, so it says nothing
        // about Calendar.current. Rewriting it relative to now would stop it checking the parse.
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 25
        components.hour = 6; components.minute = 32; components.second = 29
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        #expect(abs(found.timeIntervalSince(utc.date(from: components)!)) < 1)
    }

    /// A simulator build has no profile at all, so the reader must return nil
    /// rather than trapping — every feature downstream treats nil as "no expiry".
    @Test("Garbage and empty input yield nil, never a crash")
    func toleratesNonsense() {
        #expect(ProvisioningProfile.expirationDate(in: Data()) == nil)
        #expect(ProvisioningProfile.expirationDate(in: Data([0x00, 0x01, 0x02, 0x03])) == nil)
        #expect(ProvisioningProfile.expirationDate(in: Data(repeating: 0xFF, count: 4096)) == nil)
    }

    @Test("A plist with no expiry yields nil")
    func missingKey() {
        let without = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict><key>Name</key><string>Something</string></dict>
        </plist>
        """
        #expect(ProvisioningProfile.expirationDate(in: blob(plist: without)) == nil)
    }

    @Test("A truncated plist yields nil")
    func truncated() {
        let cut = String(plist.dropLast(40))
        #expect(ProvisioningProfile.expirationDate(in: blob(plist: cut, suffix: [])) == nil)
    }
}

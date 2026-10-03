import Foundation

/// The provisioning profile this build was signed with.
///
/// Every signed app carries `embedded.mobileprovision` in its bundle, and the
/// expiry date in it is the day the app stops launching. Reading it is the only
/// way for the app to know how long it has left — nothing else in the runtime
/// will say.
///
/// There is no such file in a simulator build, so everything here resolves to
/// `nil` there and the features that depend on it quietly do nothing.
enum ProvisioningProfile {

    /// When this build stops launching, if it is signed in a way that expires.
    static var expirationDate: Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return expirationDate(in: data)
    }

    /// Pulls the expiry out of a `.mobileprovision` file's bytes.
    ///
    /// The file is a CMS signature wrapped around an XML property list. Properly
    /// unwrapping the signature would mean dragging in Security framework work
    /// to read one date out of a payload the app already trusts — it came from
    /// its own bundle. So this finds the plist inside the blob and parses that,
    /// which is what the usual `security cms -D` incantation amounts to.
    static func expirationDate(in data: Data) -> Date? {
        guard let opening = data.range(of: Data("<plist".utf8)),
              let closing = data.range(of: Data("</plist>".utf8),
                                       in: opening.lowerBound..<data.endIndex)
        else { return nil }

        let xml = data[opening.lowerBound..<closing.upperBound]
        guard let plist = try? PropertyListSerialization.propertyList(from: xml,
                                                                     options: [],
                                                                     format: nil),
              let fields = plist as? [String: Any]
        else { return nil }

        return fields["ExpirationDate"] as? Date
    }
}

import Foundation

/// Titles the app writes itself. One constant so the code that writes them and the code that
/// refuses to suggest them cannot drift apart: otherwise typing "N" suggests "New block" forever.
enum DefaultTitles {
    /// What the `+` button and a fresh template row are called.
    static let newBlock = "New block"
}

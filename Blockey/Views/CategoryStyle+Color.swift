import SwiftUI
import UIKit

extension SRGB {
    var color: Color { Color(uiColor: uiColor) }
    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
}

/// The SwiftUI face of `CategoryStyle`. Each colour resolves per appearance, so a chip follows
/// light and dark without the view branching. 
extension CategoryStyle {
    private func dynamic(_ pick: @escaping (CategoryColorRecord) -> SRGB) -> Color {
        Color(uiColor: UIColor { traits in
            pick(colors.record(isDark: traits.userInterfaceStyle == .dark)).uiColor
        })
    }
    var spine: Color { dynamic(\.spine) }
    var fill: Color { dynamic(\.fill) }
    var border: Color { dynamic(\.border) }
    var onFill: Color { dynamic(\.onFill) }
}

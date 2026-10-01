import AppKit
import SwiftUI

/// The only source of design tokens; views never hard-code a size, radius or colour.
enum Theme {
    /// Stone's mark lives in the app target's asset catalog, so it is read from the main bundle.
    enum Brand {
        static let mark = "StoneMark"
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
    }

    enum Radius {
        static let panel: CGFloat = 20
        static let row: CGFloat = 8
        static let keyCap: CGFloat = 5
        static let hud: CGFloat = 16
    }

    enum Size {
        static let capture = CGSize(width: 600, height: 200)
        static let browse = CGSize(width: 780, height: 480)
        static let browseListWidth: CGFloat = 280
        static let footerHeight: CGFloat = 32
        static let searchFieldHeight: CGFloat = 44
        static let rowHeight: CGFloat = 46
        /// Fraction of the screen's visible height above the panel's top edge; it grows downward.
        static let panelTopFraction: CGFloat = 0.22
        static let captureFontSize: CGFloat = 15
    }

    enum Font {
        static let capture = SwiftUI.Font.system(size: Size.captureFontSize)
        static let search = SwiftUI.Font.system(size: 15)
        static let rowTitle = SwiftUI.Font.system(size: 13, weight: .medium)
        static let rowSubtitle = SwiftUI.Font.system(size: 11)
        static let previewTitle = SwiftUI.Font.system(size: 17, weight: .semibold)
        static let preview = SwiftUI.Font.system(size: 13.5)
        static let label = SwiftUI.Font.system(size: 11, weight: .medium)
        static let footer = SwiftUI.Font.system(size: 11)
    }

    enum Colors {
        static let selection = Color.accentColor.opacity(0.22)
        static let divider = Color.primary.opacity(0.08)
        static let keyCap = Color.primary.opacity(0.08)
        static let border = Color.primary.opacity(0.1)
    }

    enum Motion {
        static let hudVisible: Duration = .milliseconds(1400)
        static let searchDebounce: Duration = .milliseconds(120)
    }
}

import AppKit

/// The quick-note text area: plain text, no smart punctuation, so what you type is what lands in Markdown.
/// Its own type so the panel can find and focus it directly instead of hoping SwiftUI focus lands.
final class CaptureTextView: NSTextView {
    func configureForCapture() {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        smartInsertDeleteEnabled = false
        drawsBackground = false
        font = .systemFont(ofSize: Theme.Size.captureFontSize)
        textColor = .labelColor
        insertionPointColor = .controlAccentColor
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
    }

    /// Focus lands with the caret after any restored draft, ready to keep typing.
    func placeCaretAtEnd() {
        setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
        scrollRangeToVisible(selectedRange())
    }
}

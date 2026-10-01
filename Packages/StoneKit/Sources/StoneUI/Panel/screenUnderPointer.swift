import AppKit

/// The display under the pointer. `NSMouseInRect` counts a screen's top edge, where the menu bar
/// is and where `CGRect.contains` would miss, so the panel never opens on the wrong display.
@MainActor
func screenUnderPointer() -> NSScreen? {
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
}

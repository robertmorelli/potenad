import AppKit

extension NSColor {
  static let editorPanelBackground = NSColor(name: "EditorPanelBackground") { appearance in
    var color = NSColor.windowBackgroundColor
    appearance.performAsCurrentDrawingAppearance {
      color =
        NSColor.textBackgroundColor.blended(withFraction: 0.06, of: .black)
        ?? .windowBackgroundColor
    }
    return color
  }
}

class PanelBackgroundView: NSView {
  override func draw(_ dirtyRect: NSRect) {
    NSColor.editorPanelBackground.setFill()
    dirtyRect.intersection(bounds).fill()
  }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }
}

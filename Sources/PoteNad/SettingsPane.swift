import AppKit

private final class SettingsContentView: NSView {
  override var isFlipped: Bool { true }
}

@MainActor
final class SettingsPane: PanelBackgroundView, NSTextFieldDelegate, NSMenuDelegate {
  weak var editor: Editor?
  let family = NSPopUpButton()
  let face = NSPopUpButton()
  let size = NSTextField()
  let wrapping = NSButton(checkboxWithTitle: "Wrap at characters", target: nil, action: nil)
  let statusBar = NSButton(checkboxWithTitle: "Show status bar", target: nil, action: nil)
  let zoom = NSPopUpButton()
  private var fontNames: [String] = []
  private var familiesLoaded = false
  private var facesLoaded = false
  private var zoomLoaded = false
  private static var families: [String]?
  private static var facesByFamily: [String: [(name: String, title: String)]] = [:]
  private let number = NumberFormatter()

  init(editor: Editor) {
    self.editor = editor
    super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 270))
    number.numberStyle = .decimal
    number.maximumFractionDigits = 2
    number.usesGroupingSeparator = false
    // Only the selected font is needed to show settings. Enumerate menus on demand.
    family.addItem(withTitle: editor.baseFont.familyName ?? "Menlo")
    fontNames = [editor.baseFont.fontName]
    face.addItem(
      withTitle: editor.baseFont.fontDescriptor.object(forKey: .face) as? String ?? "Regular")
    family.menu?.delegate = self
    face.menu?.delegate = self
    size.stringValue =
      number.string(from: NSNumber(value: Double(editor.baseFont.pointSize))) ?? "12"
    size.delegate = self
    size.toolTip = "Font size in points (1–512)"
    zoom.addItem(withTitle: "\(editor.zoomPercent)%")
    zoom.menu?.delegate = self
    syncControls()
    family.target = self
    family.action = #selector(changeFamily)
    face.target = self
    face.action = #selector(changeFace)
    wrapping.target = self
    wrapping.action = #selector(changeWrap)
    statusBar.target = self
    statusBar.action = #selector(changeStatus)
    zoom.target = self
    zoom.action = #selector(changeZoom)

    let close = NSButton(title: "×", target: editor, action: #selector(Editor.showSettings(_:)))
    close.toolTip = "Close Settings (⌘,)"
    let page = NSButton(
      title: "Page Setup…", target: editor.note, action: #selector(PoteNadDocument.pageSetup(_:)))
    let content = SettingsContentView(frame: NSRect(x: 0, y: 0, width: 320, height: 280))
    close.frame = NSRect(x: 280, y: 8, width: 28, height: 24)
    content.addSubview(close)
    let rows: [(String, NSView)] = [
      ("Family:", family), ("Typeface:", face), ("Size (pt):", size),
      ("Zoom:", zoom), ("", wrapping), ("", statusBar), ("", page),
    ]
    for (index, row) in rows.enumerated() {
      let y = CGFloat(40 + index * 32)
      if !row.0.isEmpty {
        let label = NSTextField(labelWithString: row.0)
        label.alignment = .right
        label.frame = NSRect(x: 8, y: y + 3, width: 86, height: 20)
        content.addSubview(label)
      }
      row.1.frame = NSRect(x: 104, y: y, width: 200, height: 26)
      content.addSubview(row.1)
    }
    let scroll = NSScrollView(frame: bounds)
    scroll.autoresizingMask = [.width, .height]
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.drawsBackground = false
    scroll.documentView = content
    addSubview(scroll)
    widthAnchor.constraint(equalToConstant: 320).isActive = true
  }
  required init?(coder: NSCoder) { fatalError() }

  func syncControls() {
    guard let editor else { return }
    let title = "\(editor.zoomPercent)%"
    if zoom.titleOfSelectedItem != title {
      if !zoomLoaded { zoom.removeAllItems(); zoom.addItem(withTitle: title) }
      zoom.selectItem(withTitle: title)
    }
    wrapping.state = editor.wrap ? .on : .off
    statusBar.state = editor.statusVisible ? .on : .off
  }
  func menuNeedsUpdate(_ menu: NSMenu) {
    if menu === zoom.menu, !zoomLoaded {
      let selected = zoom.titleOfSelectedItem
      zoom.removeAllItems()
      zoom.addItems(withTitles: stride(from: 10, through: 500, by: 10).map { "\($0)%" })
      if let selected { zoom.selectItem(withTitle: selected) }
      zoomLoaded = true
    } else if menu === family.menu, !familiesLoaded {
      let selected = family.titleOfSelectedItem
      if Self.families == nil {
        Self.families = NSFontManager.shared.availableFontFamilies.sorted()
      }
      family.removeAllItems()
      family.addItems(withTitles: Self.families!)
      if let selected { family.selectItem(withTitle: selected) }
      familiesLoaded = true
    } else if menu === face.menu, !facesLoaded {
      let selected = editor?.baseFont.fontName
      updateFaces()
      if let selected, let index = fontNames.firstIndex(of: selected) { face.selectItem(at: index) }
    }
  }
  private func updateFaces() {
    let familyName = family.titleOfSelectedItem ?? "Menlo"
    if Self.facesByFamily[familyName] == nil {
      Self.facesByFamily[familyName] =
        (NSFontManager.shared.availableMembers(ofFontFamily: familyName) ?? []).compactMap {
          member in
          guard let name = member[0] as? String, let title = member[1] as? String else {
            return nil
          }
          return (name, title)
        }
    }
    let members = Self.facesByFamily[familyName]!
    face.removeAllItems()
    fontNames = members.map(\.name)
    face.addItems(withTitles: members.map(\.title))
    face.selectItem(withTitle: "Regular")
    facesLoaded = true
  }
  private func applyFont() {
    guard let editor else { return }
    let text = size.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let points = Double(text.replacingOccurrences(of: number.decimalSeparator, with: ".")),
      points.isFinite, (1...512).contains(points),
      fontNames.indices.contains(face.indexOfSelectedItem),
      let font = NSFont(name: fontNames[face.indexOfSelectedItem], size: points)
    else { return }
    editor.setBaseFont(font)
  }
  func controlTextDidChange(_ notification: Notification) { applyFont() }
  func controlTextDidEndEditing(_ notification: Notification) {
    guard let editor else { return }
    size.stringValue =
      number.string(from: NSNumber(value: Double(editor.baseFont.pointSize))) ?? "12"
  }
  @objc func changeFamily() {
    updateFaces()
    applyFont()
  }
  @objc func changeFace() { applyFont() }
  @objc func changeWrap() { editor?.toggleWrap(nil) }
  @objc func changeStatus() { editor?.toggleStatus(nil) }
  @objc func changeZoom() {
    if let title = zoom.titleOfSelectedItem, let percent = Int(title.dropLast()) {
      editor?.setZoom(percent)
    }
  }
}

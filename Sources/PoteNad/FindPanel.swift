import AppKit
import TextCore

final class AttachedSearchWindow: NSPanel {
  override var canBecomeKey: Bool { true }
  override func cancelOperation(_ sender: Any?) { close() }
}

final class FindPanel: NSWindowController {
  weak var editor: Editor?
  let query = NSTextField(string: UserDefaults.standard.string(forKey: "find") ?? "")
  let replacement = NSTextField(string: "")
  let matchCase = NSButton(checkboxWithTitle: "Match case", target: nil, action: nil)
  let wrap = NSButton(checkboxWithTitle: "Wrap around", target: nil, action: nil)
  let direction = NSPopUpButton()
  let replacementRow = NSStackView()
  private var savedQuery = ""
  private var savedCase = false
  private var savedWrap = true
  init(editor: Editor) {
    self.editor = editor
    let panel = AttachedSearchWindow(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 215),
      styleMask: [.borderless], backing: .buffered, defer: false)
    panel.title = "Find / Replace"
    panel.isFloatingPanel = false
    panel.isMovable = false
    panel.hasShadow = true
    panel.backgroundColor = .editorPanelBackground
    super.init(window: panel)
    let root = NSStackView()
    root.orientation = .vertical
    root.alignment = .leading
    root.spacing = 12
    root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    panel.contentView = root
    func button(_ title: String, _ action: Selector) -> NSButton {
      NSButton(title: title, target: self, action: action)
    }
    let close = button("×", #selector(dismiss))
    close.toolTip = "Close Find (Escape)"
    let row = NSStackView(views: [
      NSTextField(labelWithString: "Find:"), query, button("Find Next", #selector(next)), close,
    ])
    root.addArrangedSubview(row)
    replacementRow.addArrangedSubview(NSTextField(labelWithString: "Replace:"))
    replacementRow.addArrangedSubview(replacement)
    replacementRow.addArrangedSubview(button("Replace", #selector(replaceOne)))
    replacementRow.addArrangedSubview(button("Replace All", #selector(replaceAll)))
    root.addArrangedSubview(replacementRow)
    direction.addItems(withTitles: ["Down", "Up"])
    wrap.state = UserDefaults.standard.object(forKey: "findWrap") as? Bool == false ? .off : .on
    matchCase.state = UserDefaults.standard.bool(forKey: "findCase") ? .on : .off
    root.addArrangedSubview(NSStackView(views: [matchCase, wrap, direction]))
    query.widthAnchor.constraint(equalToConstant: 200).isActive = true
    replacement.widthAnchor.constraint(equalToConstant: 160).isActive = true
    query.target = self
    query.action = #selector(next)
    // Size to the controls instead of squeezing the replacement row into 500pt.
    panel.setContentSize(root.fittingSize)

  }
  @objc func dismiss() {
    close()
    editor?.window?.makeFirstResponder(editor?.textView)
  }
  override func close() {
    if let window { window.parent?.removeChildWindow(window) }
    super.close()
  }
  func attach(show: Bool = false) {
    guard let parent = editor?.window, let content = parent.contentView, let window else { return }
    guard show || window.parent != nil else { return }
    if window.parent !== parent { parent.addChildWindow(window, ordered: .above) }
    let bounds = parent.convertToScreen(content.frame)
    window.setFrameOrigin(
      NSPoint(x: bounds.maxX - window.frame.width, y: bounds.maxY - window.frame.height))
  }
  required init?(coder: NSCoder) { fatalError() }
  var options: NSString.CompareOptions {
    matchCase.state == .on ? [.literal] : [.literal, .caseInsensitive]
  }
  @objc func next() { find(backwards: direction.indexOfSelectedItem == 1) }
  func find(backwards: Bool) {
    guard let editor, !query.stringValue.isEmpty else {
      NSSound.beep()
      return
    }
    if query.stringValue != savedQuery {
      savedQuery = query.stringValue
      UserDefaults.standard.set(savedQuery, forKey: "find")
    }
    if (wrap.state == .on) != savedWrap {
      savedWrap = wrap.state == .on
      UserDefaults.standard.set(savedWrap, forKey: "findWrap")
    }
    if (matchCase.state == .on) != savedCase {
      savedCase = matchCase.state == .on
      UserDefaults.standard.set(savedCase, forKey: "findCase")
    }
    let text = editor.textView.string as NSString
    let selected = editor.textView.selectedRange()
    let start = backwards ? selected.location : NSMaxRange(selected)
    let range =
      backwards
      ? NSRange(location: 0, length: start) : NSRange(location: start, length: text.length - start)
    var opts = options
    if backwards { opts.insert(.backwards) }
    var result = text.range(of: query.stringValue, options: opts, range: range)
    if result.location == NSNotFound && wrap.state == .on {
      result = text.range(
        of: query.stringValue, options: opts, range: NSRange(location: 0, length: text.length))
    }
    guard result.location != NSNotFound else {
      NSSound.beep()
      return
    }
    editor.textView.setSelectedRange(result)
    editor.textView.scrollRangeToVisible(result)
    editor.textView.showFindIndicator(for: result)
  }
  @objc func replaceOne() {
    guard let editor, !query.stringValue.isEmpty else { return }
    let range = editor.textView.selectedRange()
    let selected = (editor.textView.string as NSString).substring(with: range) as NSString
    if selected.compare(query.stringValue, options: options) == .orderedSame {
      editor.textView.insertText(replacement.stringValue, replacementRange: range)
    }
    find(backwards: false)
  }
  @objc func replaceAll() {
    guard let editor, !query.stringValue.isEmpty else { return }
    let text = editor.textView.string as NSString
    var ranges = [NSRange]()
    var offset = 0
    while offset < text.length {
      let found = text.range(
        of: query.stringValue, options: options,
        range: NSRange(location: offset, length: text.length - offset))
      if found.location == NSNotFound { break }
      ranges.append(found)
      offset = NSMaxRange(found)
    }
    guard !ranges.isEmpty else {
      return
    }
    let view = editor.textView
    guard
      view.shouldChangeText(
        inRanges: ranges.map { NSValue(range: $0) },
        replacementStrings: Array(repeating: replacement.stringValue, count: ranges.count))
    else { return }
    view.undoManager?.beginUndoGrouping()
    // Coalesce layout and index work into one storage edit for bulk replacement.
    view.textStorage?.beginEditing()
    for range in ranges.reversed() {
      view.textStorage?.replaceCharacters(in: range, with: replacement.stringValue)
    }
    view.textStorage?.endEditing()
    view.didChangeText()
    view.undoManager?.endUndoGrouping()
    view.undoManager?.setActionName("Replace All")
    view.setSelectedRange(
      NSRange(location: min(ranges[0].location, view.string.utf16.count), length: 0))
  }
}

import AppKit
import TextCore

final class PlainTextView: NSTextView {
  weak var editor: Editor?
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard modifiers.contains(.command), !modifiers.contains(.option), !modifiers.contains(.control),
      let editor
    else {
      return super.performKeyEquivalent(with: event)
    }
    switch event.charactersIgnoringModifiers {
    case "=", "+": editor.zoomIn(nil)
    case "-": editor.zoomOut(nil)
    case "0": editor.zoomReset(nil)
    default: return super.performKeyEquivalent(with: event)
    }
    return true
  }
}

final class EditorScrollView: NSScrollView {
  override func tile() {
    super.tile()
    guard let text = documentView as? NSTextView else { return }
    text.minSize = contentSize
    if !text.isHorizontallyResizable {
      let size = NSSize(
        width: contentSize.width, height: max(contentSize.height, text.frame.height))
      if text.frame.size != size { text.setFrameSize(size) }
    }
  }
}

extension PlainTextView {
  override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool
  {
    guard let value = pboard.string(forType: .string) else { return false }
    insertText(
      value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"),
      replacementRange: selectedRange())
    return true
  }
}

final class Editor: NSWindowController, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate,
  NSMenuItemValidation, NSWindowDelegate
{
  let textView = PlainTextView(frame: NSRect(x: 0, y: 0, width: 850, height: 556))
  let scroll = EditorScrollView()
  let status = NSTextField(labelWithString: "")
  let statusBar = PanelBackgroundView()
  private lazy var statusHeight = statusBar.heightAnchor.constraint(equalToConstant: 24)
  var index = LineIndex()
  var wrap = UserDefaults.standard.bool(forKey: "wrap")
  var statusVisible = UserDefaults.standard.object(forKey: "status") as? Bool ?? true
  private(set) var zoomPercent = 100
  private(set) var baseFont = Editor.savedFont()
  private let paragraph: NSParagraphStyle = {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byCharWrapping
    return style
  }()
  private(set) lazy var displayFont = baseFont
  private(set) lazy var displayAttributes: [NSAttributedString.Key: Any] = [
    .font: displayFont, .paragraphStyle: paragraph, .foregroundColor: NSColor.textColor,
  ]
  private var lastStatus = ""
  static func savedFont() -> NSFont {
    let size = UserDefaults.standard.double(forKey: "fontSize")
    let validSize = size.isFinite && (1...512).contains(size) ? size : 12
    return NSFont(
      name: UserDefaults.standard.string(forKey: "fontName") ?? "Menlo", size: validSize)
      ?? .monospacedSystemFont(ofSize: validSize, weight: .regular)
  }
  var finder: FindPanel?
  private let body = NSStackView()
  private(set) var settingsPane: SettingsPane?
  private(set) var settingsVisible = false
  unowned let note: PoteNadDocument
  init(document: PoteNadDocument) {
    self.note = document
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 850, height: 580),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    super.init(window: window)
    window.delegate = self
    textView.editor = self
    window.minSize = NSSize(width: 420, height: 240)
    window.center()
    window.setFrameAutosaveName("NotepadWindow")
    let root = NSView()
    window.contentView = root
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.borderType = .noBorder
    textView.usesFontPanel = false
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isContinuousSpellCheckingEnabled = false
    textView.isGrammarCheckingEnabled = false
    textView.isAutomaticLinkDetectionEnabled = false
    textView.isAutomaticDataDetectionEnabled = false
    textView.isAutomaticTextCompletionEnabled = false
    if #available(macOS 15.0, *) { textView.writingToolsBehavior = .none }
    textView.textContainerInset = NSSize(width: 4, height: 5)
    textView.font = baseFont
    textView.isVerticallyResizable = true
    textView.minSize = .zero
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.layoutManager?.allowsNonContiguousLayout = true
    loadText(document.file.text)
    // NSTextStorage owns the live buffer after loading.
    document.file.text = ""
    textView.delegate = self
    textView.textStorage?.delegate = self
    scroll.documentView = textView
    body.translatesAutoresizingMaskIntoConstraints = false
    body.orientation = .horizontal
    body.spacing = 0
    body.alignment = .top
    body.addArrangedSubview(scroll)
    root.addSubview(body)
    root.addSubview(statusBar)
    statusBar.addSubview(status)
    statusBar.translatesAutoresizingMaskIntoConstraints = false
    scroll.translatesAutoresizingMaskIntoConstraints = false
    status.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      body.topAnchor.constraint(equalTo: root.topAnchor),
      body.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      body.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      body.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
      statusBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      statusBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      statusBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      status.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor),
      status.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor),
      status.bottomAnchor.constraint(equalTo: statusBar.bottomAnchor),
      scroll.heightAnchor.constraint(equalTo: body.heightAnchor),

      statusHeight,
    ])
    status.lineBreakMode = .byTruncatingTail
    updateStatusSize()
    status.textColor = .secondaryLabelColor
    status.isHidden = !statusVisible
    statusBar.isHidden = !statusVisible
    applyWrap()
    updateStatus()
    // Construct fixed controls with the window, so the Settings shortcut only reveals them.
    let pane = SettingsPane(editor: self)
    settingsPane = pane
    pane.isHidden = true
    body.addArrangedSubview(pane)
    pane.heightAnchor.constraint(equalTo: body.heightAnchor).isActive = true
    window.makeFirstResponder(textView)
  }
  required init?(coder: NSCoder) { fatalError() }
  func loadText(_ text: String) {
    textView.textStorage?.setAttributedString(
      NSAttributedString(string: text, attributes: displayAttributes))
    textView.defaultParagraphStyle = paragraph
    textView.typingAttributes = displayAttributes
    index.rebuild(text as NSString)
    textView.undoManager?.removeAllActions()
    updateStatus()
  }
  func textStorage(
    _ storage: NSTextStorage, willProcessEditing mask: NSTextStorageEditActions, range: NSRange,
    changeInLength delta: Int
  ) {
    // Undo can restore attributed text from before a font change. Normalize
    // only the edited span; ordinary typing must not restyle the whole file.
    if mask.contains(.editedCharacters), range.length > 0 {
      storage.setAttributes(displayAttributes, range: range)
    }
  }
  func textStorage(
    _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
    range editedRange: NSRange, changeInLength delta: Int
  ) {
    if editedMask.contains(.editedCharacters) {
      index.update(textStorage.mutableString, editedRange: editedRange, delta: delta)
    }
  }
  func undoManager(for view: NSTextView) -> UndoManager? { note.undoManager }
  func textDidChange(_ notification: Notification) {
    note.syncEditedIndicator()
    updateStatus()
  }
  func textViewDidChangeSelection(_ notification: Notification) {
    updateStatus()
  }
  func updateStatus() {
    guard statusVisible else { return }
    let p = index.position(textView.selectedRange().location)
    let value = "   Ln \(p.line), Col \(p.column)     |     \(zoomPercent)%"
    guard value != lastStatus else { return }
    lastStatus = value
    status.stringValue = value
  }
  func applyWrap() {
    scroll.hasHorizontalScroller = !wrap
    textView.isHorizontallyResizable = !wrap
    textView.autoresizingMask = wrap ? [.width] : []
    textView.textContainer?.widthTracksTextView = wrap
    if !wrap {
      textView.textContainer?.containerSize = NSSize(
        width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }
    scroll.tile()
  }
  @objc func toggleWrap(_ sender: Any?) {
    wrap.toggle()
    UserDefaults.standard.set(wrap, forKey: "wrap")
    if settingsVisible { settingsPane?.syncControls() }
    applyWrap()
  }
  @objc func toggleStatus(_ sender: Any?) {
    statusVisible.toggle()
    status.isHidden = !statusVisible
    statusBar.isHidden = !statusVisible
    updateStatusSize()
    UserDefaults.standard.set(statusVisible, forKey: "status")
    if settingsVisible { settingsPane?.syncControls() }
    updateStatus()
  }
  @objc func showSettings(_ sender: Any?) {
    settingsVisible.toggle()
    if settingsVisible {
      finder?.close()
      settingsPane?.syncControls()
      settingsPane?.isHidden = false
    } else {
      window?.makeFirstResponder(textView)
      settingsPane?.isHidden = true
    }
    // Let AppKit perform one viewport layout for the next frame; do not force
    // the entire text document to size itself just to show a sidebar.
  }
  func windowDidResize(_ notification: Notification) { finder?.attach() }
  func windowDidMove(_ notification: Notification) { finder?.attach() }
  func setBaseFont(_ font: NSFont, persist: Bool = true) {
    guard font.pointSize.isFinite, (1...512).contains(font.pointSize) else {
      return
    }
    guard baseFont != font else { return }
    baseFont = font
    if persist {
      UserDefaults.standard.set(font.fontName, forKey: "fontName")
      UserDefaults.standard.set(font.pointSize, forKey: "fontSize")
    }
    applyFont()
  }
  func updateStatusSize() {
    let scale = CGFloat(zoomPercent) / 100
    status.font = .systemFont(ofSize: 11 * scale)
    statusHeight.constant = statusVisible ? 24 * scale : 0
  }
  func applyFont() {
    updateStatusSize()
    window?.contentView?.layoutSubtreeIfNeeded()
    displayFont =
      NSFont(
        descriptor: baseFont.fontDescriptor, size: baseFont.pointSize * CGFloat(zoomPercent) / 100)
      ?? baseFont
    displayAttributes[.font] = displayFont
    textView.font = displayFont
    textView.defaultParagraphStyle = paragraph
    textView.typingAttributes = displayAttributes
    textView.scrollRangeToVisible(textView.selectedRange())
    updateStatus()
  }
  @objc func zoomIn(_ sender: Any?) { setZoom(zoomPercent + 10) }
  @objc func zoomOut(_ sender: Any?) { setZoom(zoomPercent - 10) }
  @objc func zoomReset(_ sender: Any?) { setZoom(100) }
  func setZoom(_ percent: Int) {
    let clamped = min(500, max(10, percent))
    guard clamped != zoomPercent else { return }
    zoomPercent = clamped
    if settingsVisible { settingsPane?.syncControls() }
    applyFont()
  }
  static func timestamp() -> String {
    let f = DateFormatter()
    f.dateStyle = .short
    f.timeStyle = .short
    return f.string(from: Date())
  }
  @objc func insertDate(_ sender: Any?) {
    textView.insertText(Self.timestamp(), replacementRange: textView.selectedRange())
  }
  @objc func searchWeb(_ sender: Any?) {
    let selected = (textView.string as NSString).substring(with: textView.selectedRange())
    guard !selected.isEmpty else { return }
    var url = URLComponents(string: "https://www.bing.com/search")!
    url.queryItems = [URLQueryItem(name: "q", value: selected)]
    NSWorkspace.shared.open(url.url!)
  }
  @objc func goTo(_ sender: Any?) {
    let a = NSAlert()
    a.messageText = "Go To Line"
    a.addButton(withTitle: "Go To")
    a.addButton(withTitle: "Cancel")
    let field = NSTextField(string: String(index.position(textView.selectedRange().location).line))
    field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
    a.accessoryView = field
    a.window.initialFirstResponder = field
    guard a.runModal() == .alertFirstButtonReturn else { return }
    guard let line = Int(field.stringValue), line > 0, line <= index.starts.count else {
      NSSound.beep()
      return
    }
    let range = NSRange(location: index.starts[line - 1], length: 0)
    textView.setSelectedRange(range)
    textView.scrollRangeToVisible(range)
  }
  @objc func showFind(_ sender: Any?) { showSearch(replace: false) }
  @objc func showReplace(_ sender: Any?) { showSearch(replace: true) }
  func showSearch(replace: Bool) {
    if finder == nil { finder = FindPanel(editor: self) }
    finder!.replacementRow.isHidden = !replace
    if let content = finder!.window?.contentView {
      finder!.window?.setContentSize(content.fittingSize)
    }
    let selection = textView.selectedRange()
    if selection.length > 0 {
      finder!.query.stringValue = (textView.string as NSString).substring(with: selection)
    }
    finder!.attach(show: true)
    finder!.showWindow(nil)
    finder!.window?.makeKey()
    finder!.window?.makeFirstResponder(finder!.query)
  }
  @objc func findNext(_ sender: Any?) {
    if finder == nil { showSearch(replace: false) } else { finder?.find(backwards: false) }
  }
  @objc func findPrevious(_ sender: Any?) {
    if finder == nil { showSearch(replace: false) } else { finder?.find(backwards: true) }
  }
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.action == #selector(toggleWrap(_:)) { menuItem.state = wrap ? .on : .off }
    if menuItem.action == #selector(toggleStatus(_:)) {
      menuItem.state = statusVisible ? .on : .off
    }
    if menuItem.action == #selector(zoomIn(_:)) { return zoomPercent < 500 }
    if menuItem.action == #selector(zoomOut(_:)) { return zoomPercent > 10 }
    if menuItem.action == #selector(goTo(_:)) { return !wrap }
    if menuItem.action == #selector(searchWeb(_:)) { return textView.selectedRange().length > 0 }
    return true
  }
}

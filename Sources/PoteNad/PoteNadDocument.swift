import AppKit
import TextCore
import UniformTypeIdentifiers

@objc(PoteNadDocument)
final class PoteNadDocument: NSDocument {
  var header = "&f"
  var footer = "Page &p"
  var file = TextFile()
  var editor: Editor?
  override class var autosavesInPlace: Bool { false }
  override class var autosavesDrafts: Bool { false }
  override var isDocumentEdited: Bool {
    // An empty scratch buffer has nothing to preserve; a cleared file does.
    if fileURL == nil && (editor?.textView.string ?? file.text).isEmpty { return false }
    return super.isDocumentEdited
  }
  func syncEditedIndicator() {
    for controller in windowControllers { controller.window?.isDocumentEdited = isDocumentEdited }
  }
  override func updateChangeCount(_ change: NSDocument.ChangeType) {
    super.updateChangeCount(change)
    syncEditedIndicator()
  }
  override func canClose(
    withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?,
    contextInfo: UnsafeMutableRawPointer?
  ) {
    guard isDocumentEdited else {
      super.canClose(
        withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
      return
    }
    let alert = NSAlert()
    alert.messageText = "Save changes?"
    alert.informativeText = ""
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Discard")
    alert.addButton(withTitle: "Cancel")
    switch alert.runModal() {
    case .alertFirstButtonReturn:
      // The save callback has exactly the same signature as the close callback.
      save(withDelegate: delegate, didSave: shouldCloseSelector, contextInfo: contextInfo)
    case .alertSecondButtonReturn:
      replyToClose(delegate, selector: shouldCloseSelector, context: contextInfo, allowed: true)
    default:
      replyToClose(delegate, selector: shouldCloseSelector, context: contextInfo, allowed: false)
    }
  }
  private func replyToClose(
    _ delegate: Any, selector: Selector?, context: UnsafeMutableRawPointer?, allowed: Bool
  ) {
    guard let target = delegate as? NSObject, let selector,
      let implementation = target.method(for: selector)
    else { return }
    typealias Callback =
      @convention(c) (AnyObject, Selector, AnyObject, Bool, UnsafeMutableRawPointer?) -> Void
    unsafeBitCast(implementation, to: Callback.self)(target, selector, self, allowed, context)
  }
  override func close() {
    editor?.finder?.close()
    super.close()
  }
  override func makeWindowControllers() {
    guard windowControllers.isEmpty else { return }
    let isLog = file.text.hasPrefix(".LOG")
    let controller = Editor(document: self)
    editor = controller
    addWindowController(controller)
    if isLog {
      controller.textView.setSelectedRange(
        NSRange(location: controller.textView.string.utf16.count, length: 0))
      controller.textView.insertText(
        "\n" + Editor.timestamp() + "\n", replacementRange: controller.textView.selectedRange())
    }
  }
  override func read(from url: URL, ofType typeName: String) throws {
    guard url.pathExtension.lowercased() == "txt" else {
      throw CocoaError(
        .fileReadUnsupportedScheme,
        userInfo: [NSLocalizedDescriptionKey: "PoteNad opens .txt files only."])
    }
    try super.read(from: url, ofType: typeName)
  }
  override func read(from data: Data, ofType typeName: String) throws {
    let loaded = try TextFile(data: data)
    MainActor.assumeIsolated {
      file = loaded
      editor?.loadText(loaded.text)
      if editor != nil { file.text = "" }
    }
  }
  override func data(ofType typeName: String) throws -> Data {
    var output = file
    if let editor { output.text = editor.textView.string }
    return output.data()
  }
  override func write(
    to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
    originalContentsURL absoluteOriginalContentsURL: URL?
  ) throws {
    guard url.pathExtension.lowercased() == "txt" else {
      throw CocoaError(
        .fileWriteInvalidFileName,
        userInfo: [NSLocalizedDescriptionKey: "Use the .txt filename extension."])
    }
    try super.write(
      to: url, ofType: typeName, for: saveOperation,
      originalContentsURL: absoluteOriginalContentsURL)
    MainActor.assumeIsolated { editor?.updateStatus() }
  }
  override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
    savePanel.allowedContentTypes = [.plainText]
    savePanel.allowsOtherFileTypes = false
    return true
  }
  @objc func pageSetup(_ sender: Any?) {
    let accessory = NSViewController()
    let h = NSTextField(string: header)
    let f = NSTextField(string: footer)
    let stack = NSStackView(views: [
      NSTextField(labelWithString: "Header:"), h, NSTextField(labelWithString: "Footer:"), f,
      NSTextField(
        labelWithString:
          "&f filename · &p page · &d date · &t time · &l left · &c center · &r right"),
    ])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    h.widthAnchor.constraint(equalToConstant: 420).isActive = true
    f.widthAnchor.constraint(equalToConstant: 420).isActive = true
    accessory.view = stack
    accessory.title = "Headers and Footers"
    let layout = NSPageLayout()
    layout.addAccessoryController(accessory)
    if layout.runModal(with: printInfo) == NSApplication.ModalResponse.OK.rawValue {
      header = h.stringValue
      footer = f.stringValue
    }
  }
  override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws
    -> NSPrintOperation
  {
    let info = printInfo.copy() as! NSPrintInfo
    info.horizontalPagination = .fit
    info.isVerticallyCentered = false
    let width = info.paperSize.width - info.leftMargin - info.rightMargin
    let view = PrintTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
    view.headerTemplate = header
    view.footerTemplate = footer
    view.filename = displayName
    info.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] = true
    view.isRichText = false
    view.string = editor?.textView.string ?? file.text
    view.font = editor?.baseFont ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
    view.defaultParagraphStyle = editor?.textView.defaultParagraphStyle
    if let style = view.defaultParagraphStyle {
      view.textStorage?.addAttribute(
        .paragraphStyle, value: style, range: NSRange(location: 0, length: view.string.utf16.count))
    }
    view.textContainer?.containerSize = NSSize(
      width: width, height: CGFloat.greatestFiniteMagnitude)
    view.layoutManager?.ensureLayout(for: view.textContainer!)
    let height = view.layoutManager!.usedRect(for: view.textContainer!).height + 20
    view.setFrameSize(NSSize(width: width, height: height))
    return NSPrintOperation(view: view, printInfo: info)
  }
}

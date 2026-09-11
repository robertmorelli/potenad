import AppKit
import TextCore

#if DEBUG
  @MainActor final class CloseProbe: NSObject {
    var allowed: Bool?
    @objc func document(
      _ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?
    ) { allowed = shouldClose }
  }
  func tryRead(_ url: URL) -> String { try! String(contentsOf: url, encoding: .utf8) }
  @MainActor func smokeTest() throws {
    let scratch = PoteNadDocument()
    scratch.makeWindowControllers()
    let scratchView = scratch.editor!.textView
    precondition(!scratch.isDocumentEdited, "Fresh scratch buffer must not prompt")
    scratchView.insertText("temporary", replacementRange: NSRange(location: 0, length: 0))
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    precondition(scratch.isDocumentEdited, "Nonempty scratch buffer must prompt")
    scratchView.breakUndoCoalescing()
    scratchView.insertText(
      "", replacementRange: NSRange(location: 0, length: scratchView.string.utf16.count))
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    precondition(!scratch.isDocumentEdited, "Emptied scratch buffer must not prompt")
    precondition(
      !scratch.editor!.window!.isDocumentEdited, "Empty scratch buffer must clear close-button dot")
    scratchView.undoManager?.undo()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    precondition(scratch.editor!.window!.isDocumentEdited, "Undoing deletion must restore dot")
    scratchView.undoManager?.redo()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    precondition(!scratch.editor!.window!.isDocumentEdited, "Redoing deletion must clear dot")
    scratch.fileURL = URL(fileURLWithPath: "/tmp/notepad-regression.txt")
    precondition(scratch.isDocumentEdited, "Clearing a saved file must still prompt")
    precondition(!PoteNadDocument.autosavesDrafts, "Scratch buffers must not become drafts")
    let document = PoteNadDocument()
    document.file = TextFile(text: "first\nsecond\nfirst")
    document.makeWindowControllers()
    precondition(document.windowControllers.count == 1, "Document must own its editor window")
    let editor = document.editor!
    editor.window!.contentView!.layoutSubtreeIfNeeded()
    // A narrow line should consume part of the second word rather than move it whole.
    let wrapStorage = NSTextStorage(
      string: "abc defghij",
      attributes: [.font: editor.baseFont, .paragraphStyle: editor.textView.defaultParagraphStyle!])
    let wrapLayout = NSLayoutManager()
    let charWidth = ("a" as NSString).size(withAttributes: [.font: editor.baseFont]).width
    let wrapContainer = NSTextContainer(containerSize: NSSize(width: charWidth * 6.5, height: 200))
    wrapContainer.lineFragmentPadding = 0
    wrapLayout.addTextContainer(wrapContainer)
    wrapStorage.addLayoutManager(wrapLayout)
    wrapLayout.ensureLayout(for: wrapContainer)
    var firstLine = NSRange()
    _ = wrapLayout.lineFragmentRect(forGlyphAt: 0, effectiveRange: &firstLine)
    precondition(
      firstLine.length > 4 && firstLine.length < wrapStorage.length,
      "Wrap must break within the second word")
    precondition(
      editor.scroll.frame.height > 100 && editor.textView.frame.width > 100,
      "Editor must fill window")
    editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
    editor.textView.insertText("hello\n", replacementRange: editor.textView.selectedRange())
    precondition(editor.index.starts == [0, 6, 12, 19])
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    precondition(document.isDocumentEdited, "Typing must mark document dirty")
    editor.textView.undoManager?.undo()
    precondition(editor.textView.string == "first\nsecond\nfirst", "Typing undo")
    let finder = FindPanel(editor: editor)
    finder.query.stringValue = "first"
    finder.replacement.stringValue = "changed\nline"
    finder.replaceAll()
    precondition(editor.textView.string == "changed\nline\nsecond\nchanged\nline", "Replace all")
    editor.textView.undoManager?.undo()
    precondition(editor.textView.string == "first\nsecond\nfirst", "Replace all undo")
    var expected = LineIndex()
    expected.rebuild(editor.textView.string as NSString)
    precondition(editor.index.starts == expected.starts, "Undo restores line index")
    editor.textView.undoManager?.redo()
    expected.rebuild(editor.textView.string as NSString)
    precondition(editor.index.starts == expected.starts, "Redo restores line index")
    let data = try document.data(ofType: "Plain Text")
    let decoded = try TextFile(data: data)
    precondition(decoded.text == editor.textView.string)
    editor.toggleWrap(nil)
    editor.toggleWrap(nil)
    precondition(editor.textView.frame.width > 100)
    // Font size and zoom are independent, and neither changes saved text or undo.
    let fontDocument = PoteNadDocument()
    fontDocument.file = TextFile(text: "abc defghij\nsecond line")
    fontDocument.makeWindowControllers()
    let fontEditor = fontDocument.editor!
    let view = fontEditor.textView
    let originalText = view.string
    view.setSelectedRange(NSRange(location: 4, length: 3))
    fontEditor.setBaseFont(NSFont(name: "Menlo", size: 20)!, persist: false)
    for _ in 0..<10 { fontEditor.zoomIn(nil) }
    precondition(fontEditor.zoomPercent == 200 && view.font!.pointSize == 40)
    precondition(fontEditor.status.font!.pointSize == 22, "Status text must scale with zoom")
    precondition(fontEditor.statusBar.frame.minY == 0, "Status bar must touch the window bottom")
    precondition(fontEditor.status.frame.minY == 0, "Status text must touch the bar bottom")
    precondition(fontEditor.statusBar.frame.height == 48, "Status bar must grow to fit zoomed text")

    fontEditor.setBaseFont(NSFont(name: "Menlo", size: 15)!, persist: false)
    precondition(view.font!.pointSize == 30, "Changing font at 200% must not compound zoom")
    fontEditor.zoomReset(nil)
    precondition(view.font!.pointSize == 15 && fontEditor.zoomPercent == 100)
    precondition(
      fontEditor.status.font!.pointSize == 11 && fontEditor.statusBar.frame.height == 24,
      "Reset must restore status size")
    precondition(
      view.selectedRange() == NSRange(location: 4, length: 3), "Font changes preserve selection")
    precondition(
      view.string == originalText && !fontDocument.isDocumentEdited,
      "Display changes never edit file")
    view.breakUndoCoalescing()
    view.insertText("NEW", replacementRange: view.selectedRange())
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    fontEditor.setZoom(150)
    view.undoManager?.undo()
    precondition(view.string == originalText, "Font changes must not steal text undo")
    view.textStorage!.enumerateAttribute(
      .font, in: NSRange(location: 0, length: view.string.utf16.count)
    ) { value, _, _ in
      precondition((value as! NSFont).pointSize == 22.5, "Undo must retain current display size")
    }
    view.undoManager?.redo()
    precondition(view.string.contains("NEW"))
    precondition((view.typingAttributes[.font] as! NSFont).pointSize == 22.5)
    for percent in [10, 500, 100] {
      fontEditor.setZoom(percent)
      for enabled in [true, false, true] {
        fontEditor.wrap = enabled
        fontEditor.applyWrap()
        precondition(
          view.frame.width.isFinite && view.frame.width >= fontEditor.scroll.contentSize.width)
      }
    }
    fontEditor.setZoom(100)
    let zoomKey = NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
      context: nil, characters: "=", charactersIgnoringModifiers: "=", isARepeat: false, keyCode: 24
    )!
    precondition(
      view.performKeyEquivalent(with: zoomKey) && fontEditor.zoomPercent == 110,
      "Command-equals must zoom")
    let picker = SettingsPane(editor: fontEditor)
    picker.layoutSubtreeIfNeeded()
    precondition(picker.size.stringValue == "15", "Font picker must show base size")
    let windowCount = NSApp.windows.count
    fontEditor.showSettings(nil)
    precondition(fontEditor.settingsPane!.window === fontEditor.window)
    precondition(NSApp.windows.count == windowCount, "Settings must not create a window")
    let pane = fontEditor.settingsPane!
    pane.size.stringValue = "18"
    pane.controlTextDidChange(
      Notification(name: NSControl.textDidChangeNotification, object: pane.size))
    precondition(fontEditor.baseFont.pointSize == 18, "Size must apply while typing")
    pane.menuNeedsUpdate(pane.zoom.menu!)
    pane.zoom.selectItem(withTitle: "150%")
    pane.changeZoom()
    precondition(fontEditor.zoomPercent == 150)
    let previousWrap = fontEditor.wrap
    pane.changeWrap()
    precondition(fontEditor.wrap != previousWrap)
    fontEditor.showSettings(nil)
    precondition(
      !fontEditor.settingsVisible && fontEditor.settingsPane === pane && pane.isHidden
        && fontEditor.baseFont.pointSize == 18)
    fontEditor.setZoom(999)
    precondition(fontEditor.zoomPercent == 500)
    fontEditor.setZoom(-10)
    precondition(fontEditor.zoomPercent == 10)

    // Finder boundaries, case handling, wrap-around and bulk undo.
    let search = FindPanel(editor: fontEditor)
    fontEditor.loadText("One two one")
    search.query.stringValue = "one"
    search.matchCase.state = .off
    search.wrap.state = .off
    view.setSelectedRange(NSRange(location: 0, length: 0))
    search.find(backwards: false)
    precondition(view.selectedRange() == NSRange(location: 0, length: 3))
    search.find(backwards: false)
    precondition(view.selectedRange().location == 8)
    search.find(backwards: false)
    precondition(view.selectedRange().location == 8)
    search.wrap.state = .on
    search.find(backwards: false)
    precondition(view.selectedRange().location == 0)
    search.find(backwards: true)
    precondition(view.selectedRange().location == 8)
    search.matchCase.state = .on
    view.setSelectedRange(NSRange(location: 0, length: 0))
    search.find(backwards: false)
    precondition(view.selectedRange().location == 8)

    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.setString("pasted\r\ntext\r", forType: .string)
    view.selectAll(nil)
    precondition(view.readSelection(from: pasteboard, type: .string))
    precondition(view.string == "pasted\ntext\n", "Paste must normalize CRLF and CR")
    pasteboard.releaseGlobally()
    fontEditor.loadText("One two one")

    search.attach(show: true)
    precondition(search.window!.parent === fontEditor.window)
    let parentBounds = fontEditor.window!.convertToScreen(fontEditor.window!.contentView!.frame)
    precondition(abs(search.window!.frame.maxX - parentBounds.maxX) < 1)
    precondition(abs(search.window!.frame.maxY - parentBounds.maxY) < 1)
    fontEditor.window!.setContentSize(NSSize(width: 640, height: 480))
    search.attach()
    let resizedBounds = fontEditor.window!.convertToScreen(fontEditor.window!.contentView!.frame)
    precondition(abs(search.window!.frame.maxX - resizedBounds.maxX) < 1)
    search.close()
    search.attach()
    precondition(
      search.window!.parent == nil && !search.window!.isVisible,
      "Resize must not reopen closed search")
    let appDelegate = AppDelegate()
    appDelegate.buildMenus()
    let settingsMenu = NSApp.mainMenu!.items.first { $0.submenu?.title == "Settings" }!.submenu!
    precondition(settingsMenu.items.first!.keyEquivalent == ",")
    precondition(
      !NSApp.mainMenu!.items.contains { ["Format", "View"].contains($0.submenu?.title ?? "") })

    // Real disk saves, reopens and rejected extensions (all disposable fixtures).
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("roundtrip.txt")
    try fontDocument.write(
      to: fileURL, ofType: "Plain Text", for: .saveAsOperation, originalContentsURL: nil)
    precondition(tryRead(fileURL) == "One two one")
    let reopened = PoteNadDocument()
    try reopened.read(from: fileURL, ofType: "Plain Text")
    reopened.makeWindowControllers()
    precondition(reopened.editor!.textView.string == "One two one")
    // Revert/reload must update an existing editor too.
    try reopened.read(from: Data("updated\r\ntext".utf8), ofType: "Plain Text")
    precondition(reopened.editor!.textView.string == "updated\ntext")
    precondition(reopened.editor!.index.starts == [0, 8])
    let panel = NSSavePanel()
    precondition(reopened.prepareSavePanel(panel))
    precondition(panel.accessoryView == nil, "Save options belong in Settings")
    precondition(AppDelegate().applicationShouldTerminateAfterLastWindowClosed(NSApp))
    let probe = CloseProbe()
    for (response, allowed) in [
      (NSApplication.ModalResponse.alertThirdButtonReturn, false), (.alertSecondButtonReturn, true),
    ] {
      probe.allowed = nil
      DispatchQueue.main.async { NSApp.stopModal(withCode: response) }
      scratch.canClose(
        withDelegate: probe,
        shouldClose: #selector(CloseProbe.document(_:shouldClose:contextInfo:)), contextInfo: nil)
      precondition(
        probe.allowed == allowed, "Close prompt must preserve Cancel and Discard behavior")
    }
    print(
      "AppKit checks passed: fonts, zoom, typing attributes, undo/redo, wrapping, dirty state, search, file saves/reload, and dialogs."
    )
  }
#endif

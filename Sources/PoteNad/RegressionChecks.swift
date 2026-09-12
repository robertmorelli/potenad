import AppKit
import TextCore

#if DEBUG
  func tryRead(_ url: URL) -> Data { try! Data(contentsOf: url) }

  @MainActor func smokeTest() throws {
    let scratch = PoteNadDocument()
    scratch.makeWindowControllers()
    let scratchView = scratch.editor!.textView
    precondition(!scratch.isDocumentEdited, "Fresh scratch buffer must not prompt")
    scratchView.insertText("temporary", replacementRange: NSRange(location: 0, length: 0))
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    precondition(scratch.isDocumentEdited, "Nonempty scratch buffer must be marked edited")
    scratchView.breakUndoCoalescing()
    scratchView.insertText(
      "", replacementRange: NSRange(location: 0, length: scratchView.string.utf16.count))
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    precondition(!scratch.isDocumentEdited, "Emptied scratch buffer must not prompt")
    precondition(PoteNadDocument.autosavesInPlace, "Saved documents must support autosave")
    precondition(PoteNadDocument.autosavesDrafts, "Untitled documents must support recovery")
    precondition(PoteNadDocument.preservesVersions, "Saved documents must support versions")

    let document = PoteNadDocument()
    document.file = TextFile(text: "first\nsecond\nfirst")
    document.makeWindowControllers()
    let editor = document.editor!
    let view = editor.textView
    editor.window!.contentView!.layoutSubtreeIfNeeded()
    precondition(document.windowControllers.count == 1, "Document must own its editor window")
    precondition(view.usesFindBar, "Editor must use AppKit's native find bar")
    precondition(
      editor.scroll.frame.height > 100 && view.frame.width > 100, "Editor must fill window")

    editor.wrap = true
    editor.applyWrap()
    precondition(view.textContainer!.widthTracksTextView, "Word wrap must track the editor width")
    editor.toggleWrap(nil)
    precondition(!view.textContainer!.widthTracksTextView && editor.scroll.hasHorizontalScroller)
    editor.toggleWrap(nil)

    view.setSelectedRange(NSRange(location: 0, length: 0))
    view.insertText("hello\n", replacementRange: view.selectedRange())
    precondition(editor.index.starts == [0, 6, 12, 19])
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    precondition(document.isDocumentEdited, "Typing must mark document dirty")
    view.undoManager?.undo()
    precondition(view.string == "first\nsecond\nfirst", "Typing undo")

    let originalText = view.string
    view.setSelectedRange(NSRange(location: 4, length: 3))
    editor.setBaseFont(NSFont(name: "Menlo", size: 15)!)
    editor.setZoom(200)
    precondition(view.font!.pointSize == 30)
    precondition(editor.status.font!.pointSize == NSFont.smallSystemFontSize)
    precondition(
      editor.statusBar.frame.height == 24, "Editor zoom must not resize interface chrome")
    precondition(view.selectedRange() == NSRange(location: 4, length: 3))
    precondition(view.string == originalText, "Display changes must not edit text")
    editor.zoomReset(nil)
    for percent in [10, 500, 100] {
      editor.setZoom(percent)
      precondition(editor.zoomPercent == percent)
    }

    let zoomKey = NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
      context: nil, characters: "=", charactersIgnoringModifiers: "=", isARepeat: false,
      keyCode: 24)!
    precondition(view.performKeyEquivalent(with: zoomKey) && editor.zoomPercent == 110)

    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.setString("pasted\r\ntext\r", forType: .string)
    view.selectAll(nil)
    precondition(view.readSelection(from: pasteboard, type: .string))
    precondition(view.string == "pasted\ntext\n", "Paste must normalize line endings internally")
    pasteboard.releaseGlobally()

    let appDelegate = AppDelegate()
    appDelegate.buildMenus()
    let menuTitles = NSApp.mainMenu!.items.compactMap(\.submenu?.title)
    precondition(menuTitles == ["PoteNad", "File", "Edit", "Format", "View", "Window", "Help"])
    let appMenu = NSApp.mainMenu!.items[0].submenu!
    precondition(appMenu.items.contains { $0.title == "Settings…" && $0.keyEquivalent == "," })
    precondition(!menuTitles.contains("Settings"), "Settings must not be a top-level menu")
    let editMenu = NSApp.mainMenu!.items[2].submenu!
    precondition(!editMenu.items.contains { $0.title.contains("Bing") })
    precondition(!appDelegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("roundtrip.log")
    document.file.encoding = .utf16LittleEndian
    document.file.lineEnding = .crlf
    editor.loadText("One\ntwo\n")
    try document.write(
      to: fileURL, ofType: "Plain Text", for: .saveAsOperation, originalContentsURL: nil)
    let expected = try TextFile(
      text: "One\ntwo\n", encoding: .utf16LittleEndian, lineEnding: .crlf
    ).data()
    precondition(tryRead(fileURL) == expected, "Disk save must preserve chosen serialization")
    let reopened = PoteNadDocument()
    try reopened.read(from: fileURL, ofType: "Plain Text")
    reopened.makeWindowControllers()
    precondition(reopened.editor!.textView.string == "One\ntwo\n")
    precondition(reopened.file.encoding == .utf16LittleEndian)
    precondition(reopened.file.lineEnding == .crlf)
    let panel = NSSavePanel()
    precondition(reopened.prepareSavePanel(panel) && panel.accessoryView != nil)
    precondition(panel.allowsOtherFileTypes, "Save panel must permit other plain-text extensions")

    print(
      "AppKit checks passed: native menus/find, settings placement, fonts, zoom, wrapping, dirty state, encoding, line endings, disk saves, and document lifecycle."
    )
  }
#endif

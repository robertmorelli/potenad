import AppKit
import TextCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    if let path = Bundle.main.path(forResource: "PoteNad", ofType: "icns") {
      let icon = NSImage(contentsOfFile: path)
      NSApp.applicationIconImage = icon
      let dockView = NSImageView(frame: NSRect(origin: .zero, size: NSApp.dockTile.size))
      dockView.image = icon
      dockView.imageScaling = .scaleProportionallyUpOrDown
      NSApp.dockTile.contentView = dockView
      NSApp.dockTile.display()
    }
    NSWindow.allowsAutomaticWindowTabbing = false
    buildMenus()
    if NSDocumentController.shared.documents.isEmpty {
      NSDocumentController.shared.newDocument(nil)
    }
    NSApp.activate(ignoringOtherApps: true)
  }
  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
  func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    if !flag {
      if NSDocumentController.shared.documents.isEmpty {
        NSDocumentController.shared.newDocument(nil)
      } else {
        NSDocumentController.shared.documents.forEach { $0.showWindows() }
      }
    }
    return true
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
  func buildMenus() {
    let bar = NSMenu()
    NSApp.mainMenu = bar
    func menu(_ title: String) -> NSMenu {
      let item = NSMenuItem()
      bar.addItem(item)
      let m = NSMenu(title: title)
      item.submenu = m
      return m
    }
    func add(
      _ m: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
      _ modifiers: NSEvent.ModifierFlags = .command
    ) {
      let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
      i.keyEquivalentModifierMask = modifiers
      m.addItem(i)
    }
    let app = menu("PoteNad")
    add(app, "About PoteNad", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
    app.addItem(.separator())
    add(app, "Hide PoteNad", #selector(NSApplication.hide(_:)), "h")
    add(app, "Quit PoteNad", #selector(NSApplication.terminate(_:)), "q")
    let file = menu("File")
    add(file, "New", #selector(NSDocumentController.newDocument(_:)), "n")
    add(
      file, "New Window", #selector(NSDocumentController.newDocument(_:)), "n", [.command, .shift])
    add(file, "Open…", #selector(NSDocumentController.openDocument(_:)), "o")
    add(file, "Save", #selector(NSDocument.save(_:)), "s")
    add(file, "Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift])
    file.addItem(.separator())
    add(file, "Print…", #selector(PoteNadDocument.printDocument(_:)), "p")
    file.addItem(.separator())
    add(file, "Close", #selector(NSWindow.performClose(_:)), "w")
    let edit = menu("Edit")
    add(edit, "Undo", Selector(("undo:")), "z")
    add(edit, "Redo", Selector(("redo:")), "z", [.command, .shift])
    edit.addItem(.separator())
    add(edit, "Cut", #selector(NSText.cut(_:)), "x")
    add(edit, "Copy", #selector(NSText.copy(_:)), "c")
    add(edit, "Paste", #selector(NSText.paste(_:)), "v")
    add(edit, "Delete", #selector(NSText.delete(_:)))
    edit.addItem(.separator())
    add(edit, "Search with Bing", #selector(Editor.searchWeb(_:)), "e")
    add(edit, "Find…", #selector(Editor.showFind(_:)), "f")
    add(edit, "Find Next", #selector(Editor.findNext(_:)), "g")
    add(edit, "Find Previous", #selector(Editor.findPrevious(_:)), "g", [.command, .shift])
    add(edit, "Replace…", #selector(Editor.showReplace(_:)), "h", [.command, .option])
    add(edit, "Go To…", #selector(Editor.goTo(_:)), "l")
    edit.addItem(.separator())
    add(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
    add(edit, "Time/Date", #selector(Editor.insertDate(_:)), "\u{F708}", [])
    let settings = menu("Settings")
    add(settings, "Settings…", #selector(Editor.showSettings(_:)), ",")
    settings.addItem(.separator())
    add(settings, "Zoom In", #selector(Editor.zoomIn(_:)), "=")
    add(settings, "Zoom Out", #selector(Editor.zoomOut(_:)), "-")
    add(settings, "Restore Default Zoom", #selector(Editor.zoomReset(_:)), "0")
    let help = menu("Help")
    add(help, "PoteNad Help", #selector(AppDelegate.help(_:)))
    help.items.last?.target = self
  }
  @objc func help(_ sender: Any?) {
    let a = NSAlert()
    a.messageText = "PoteNad"
    a.informativeText =
      "A native plain-text editor for .txt files.\n\nUse File to open, save, and print. Edit contains Find, Replace, Go To, and Time/Date (F5). Settings (Command-comma) contains font, wrapping, zoom, status bar, and page setup.\n\nFiles use UTF-8 and macOS (LF) line endings. A file beginning with .LOG receives a timestamp when opened."
    a.runModal()
  }
}

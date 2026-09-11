# PoteNad

A small native macOS `.txt` editor written in Swift and AppKit. Requires macOS 13 or newer. No third-party dependencies.

Build the app with `./scripts/build.sh`, then open `build/PoteNad.app`. Open `Package.swift` in Xcode to work on the source. The build script produces an optimized, locally ad-hoc signed app for your Mac's architecture.

## Features

The baseline is classic Windows 10 Notepad:

- New documents and independent windows; Open, Save, Save As, Close, and unsaved-change prompts.
- Undo/redo, cut/copy/paste/delete, and select all.
- Find next/previous, direction, match case, wrap-around search, replace, and replace all.
- Go To Line (with word wrap off), F5 Time/Date, and `.LOG` timestamps when opening.
- Character wrapping, font selection, zoom from 10–500% in exact 10% steps, and an optional line/column and zoom status bar.
- Page setup, printing, and configurable headers/footers: `&f`, `&p`, `&d`, `&t`, `&l`, `&c`, `&r`, and `&&`.
- Search the selected text with Bing, only when explicitly invoked.
- UTF-8 only. UTF-8 BOMs are accepted on open and omitted on save. Non-UTF-8 files are rejected.
- macOS (LF) line endings only on save. CRLF and CR files normalize to LF when opened. New files default to UTF-8.

Native macOS adaptations: Command keyboard shortcuts, standard Mac file/print dialogs and an inline Settings sidebar, separate windows for New, and redo. All line endings are normalized to LF on save. Only `.txt` files are accepted. There are no tabs, rich text, syntax highlighting, spell checking, automatic substitutions, AI tools, plugins, or autosave.

## Performance

Uses AppKit's plain `NSTextView` directly with noncontiguous layout. Text lives in one text storage after loading. The line index updates after edits; cursor status uses binary search. Replace All batches storage edits so layout and indexing run once. The app does no polling or background network work. File decoding/encoding and storage edits are synchronous; extremely large files can still pause the UI, and performance is not guaranteed against Windows Notepad on other hardware.

## Verification

```
./scripts/check.sh
```

Tests cover UTF-8/line-ending round trips, Unicode, and non-UTF-8 rejection, 2,000 randomized incremental line-index edits, and a 400,000-line document. The debug-only AppKit checks cover editor geometry, empty-buffer indicators, typing and replacement undo/redo, line-index consistency, actual disk saves and reloads, paste normalization, search boundaries, character wrapping, and font/zoom interactions. UI checks also exercise inline settings and attached search.

Reference baseline: [Microsoft's Windows 10 Notepad improvements](https://blogs.windows.com/windows-insider/2018/07/11/announcing-windows-10-insider-preview-build-17713/) and [Notepad printing help](https://support.microsoft.com/en-us/windows/help-in-notepad-4d68c388-2ff2-0e7f-b706-35fb2ab88a8c).

The release launch check runs the actual app lifecycle, verifies a registered and visible editor window, then exits. Reopening the app after closing its last window creates a new document.

Empty untitled buffers close without a save prompt, including after typing and deleting everything. Clearing an existing file still requires save/discard confirmation. Closing the last editor window exits the app. Files always use UTF-8 with macOS (LF) line endings.

## Font sizing

Settings → Settings… (Command-comma) chooses family, typeface, and point size (1–512 pt) with changes applied immediately. The chosen size is the size at 100% zoom; zoom never changes that preference. Command + equals/plus zooms in, Command + minus zooms out, and Command + 0 resets zoom. Display changes preserve text, selection, and text undo. Invalid font sizes left by an older build fall back to 12 pt.

## Source layout

The app uses direct AppKit controls, with separate files for menus, document I/O, the editor, font selection, search, and printing. Regression checks are compiled only into debug builds. Text encoding and line indexing live in the small TextCore target; no external packages are used.

## License

MIT — see [LICENSE](LICENSE).

Find and Replace attach to the editor’s upper-right corner and follow its position and size. Escape or × dismisses search. All editor settings and page setup are collected in the Settings sidebar (Command-comma toggles it). The icon is a solid black circle on a fully transparent canvas.

Settings is part of the editor window, with no title, explanatory subtitle, or Apply/Cancel step. Valid size edits take effect while typing; font, wrapping, zoom, and status changes apply immediately. Invalid size input keeps the last valid size and is reset when the field loses focus.

Find and Settings use a slightly darker background than the editor. Closing a changed document uses a compact Save/Discard/Cancel prompt without an explanatory paragraph.

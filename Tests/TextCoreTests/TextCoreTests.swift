import XCTest

@testable import TextCore

final class TextCoreTests: XCTestCase {
  func testUTF8RoundTrip() throws {
    let content = "café 👩🏽‍💻 中文\nsecond\n"
    let file = TextFile(text: content)
    XCTAssertEqual(file.data(), Data(content.utf8))
    XCTAssertEqual(try TextFile(data: file.data()).text, content)
    let withBOM = Data([0xEF, 0xBB, 0xBF]) + Data(content.utf8)
    XCTAssertEqual(try TextFile(data: withBOM).data(), Data(content.utf8))
  }
  func testAllLineEndingsSaveAsLF() throws {
    for input in ["a\r\nb\r\n", "a\rb\r", "a\nb\n", "a\r\nb\r"] {
      let loaded = try TextFile(data: Data(input.utf8))
      XCTAssertEqual(loaded.text, "a\nb\n")
      XCTAssertEqual(loaded.data(), Data("a\nb\n".utf8))
      // Also normalize CR introduced directly into the buffer.
      XCTAssertEqual(TextFile(text: input).data(), Data("a\nb\n".utf8))
    }
  }
  func testNonUTF8Rejected() {
    for bytes: [UInt8] in [
      [0xFF, 0xFE, 0x61, 0x00], [0xFE, 0xFF, 0x00, 0x61], [0xE9], [0xC3, 0x28],
    ] {
      XCTAssertThrowsError(try TextFile(data: Data(bytes)))
    }
  }
  func testIncrementalIndexAgainstFullRebuild() {
    let text = NSMutableString(string: "one\ntwo\n👋 three\n")
    var incremental = LineIndex()
    incremental.rebuild(text)
    var seed: UInt64 = 42
    func random(_ bound: Int) -> Int {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1
      return Int(seed >> 32) % bound
    }
    for _ in 0..<2000 {
      let start = random(text.length + 1)
      let count = random(text.length - start + 1)
      let replacement = ["", "\n", "abc", "\n\nx\n", "long text"][random(5)]
      let length = (replacement as NSString).length
      text.replaceCharacters(in: NSRange(location: start, length: count), with: replacement)
      incremental.update(
        text, editedRange: NSRange(location: start, length: length), delta: length - count)
      var rebuilt = LineIndex()
      rebuilt.rebuild(text)
      XCTAssertEqual(incremental.starts, rebuilt.starts)
      for offset in 0...text.length {
        XCTAssertEqual(incremental.position(offset).line, rebuilt.position(offset).line)
        XCTAssertEqual(incremental.position(offset).column, rebuilt.position(offset).column)
      }
    }
  }
  func testLargeDocumentIndex() {
    let text = String(repeating: "a short line of plain text\n", count: 400_000) as NSString
    var index = LineIndex()
    index.rebuild(text)
    XCTAssertEqual(index.starts.count, 400_001)
    XCTAssertEqual(index.position(text.length).line, 400_001)
    measure { for i in stride(from: 0, to: text.length, by: 1000) { _ = index.position(i) } }
  }
}

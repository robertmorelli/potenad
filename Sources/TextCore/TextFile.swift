import Foundation

public struct TextFile: Sendable {
  public var text: String
  public init(text: String = "") { self.text = text }
  public init(data: Data) throws {
    let bytes = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data
    guard let decoded = String(data: bytes, encoding: .utf8) else {
      throw CocoaError(
        .fileReadInapplicableStringEncoding,
        userInfo: [NSLocalizedDescriptionKey: "PoteNad opens UTF-8 text files only."])
    }
    text = Self.normalize(decoded)
  }
  public func data() -> Data { Data(Self.normalize(text).utf8) }
  private static func normalize(_ text: String) -> String {
    guard text.utf8.contains(13) else { return text }
    return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(
      of: "\r", with: "\n")
  }
}

/// Sorted UTF-16 line offsets; selection changes use binary search, never a document scan.
public struct LineIndex {
  public private(set) var starts = [0]
  public init() {}
  public mutating func rebuild(_ text: NSString) {
    starts = [0]
    for i in 0..<text.length where text.character(at: i) == 10 { starts.append(i + 1) }
  }
  public mutating func update(_ text: NSString, editedRange: NSRange, delta: Int) {
    let oldEnd = NSMaxRange(editedRange) - delta
    let lower = upperBound(editedRange.location)
    let upper = upperBound(oldEnd)
    let added = (editedRange.location..<NSMaxRange(editedRange)).compactMap {
      text.character(at: $0) == 10 ? $0 + 1 : nil
    }
    starts.replaceSubrange(lower..<upper, with: added)
    if delta != 0 {
      for i in (lower + added.count)..<starts.count { starts[i] += delta }
    }
  }
  private func upperBound(_ offset: Int) -> Int {
    var lo = 0
    var hi = starts.count
    while lo < hi {
      let mid = (lo + hi) / 2
      if starts[mid] <= offset { lo = mid + 1 } else { hi = mid }
    }
    return lo
  }
  public func position(_ offset: Int) -> (line: Int, column: Int) {
    let i = max(0, upperBound(offset) - 1)
    return (i + 1, offset - starts[i] + 1)
  }
}

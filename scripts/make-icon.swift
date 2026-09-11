import AppKit

let directory = URL(fileURLWithPath: "build/PoteNad.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current!.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        NSColor.black.setFill()
        let inset = CGFloat(pixels) * 72 / 1024
        NSBezierPath(ovalIn: NSRect(x: inset, y: inset, width: CGFloat(pixels) - 2 * inset,
            height: CGFloat(pixels) - 2 * inset)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(
            to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}

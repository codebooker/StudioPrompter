import AppKit
// App Store icons must be square and opaque. Draw the same code-native wordmark
// symbol as the Mac icon, using exact pixel dimensions independent of Retina.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 0.10, green: 0.115, blue: 0.14, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
NSColor(calibratedRed: 1, green: 0.49, blue: 0.29, alpha: 1).setFill()
for (index, width) in [480.0, 400, 480, 300].enumerated() {
    NSBezierPath(roundedRect: NSRect(x: 320, y: 710 - Double(index) * 140, width: width, height: 55), xRadius: 24, yRadius: 24).fill()
}
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 150, y: 620)); arrow.line(to: NSPoint(x: 250, y: 550)); arrow.line(to: NSPoint(x: 150, y: 480)); arrow.close(); arrow.fill()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: output)

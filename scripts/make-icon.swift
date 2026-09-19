import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let pixels = size * factor
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(calibratedRed: 0.10, green: 0.115, blue: 0.14, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 34, y: 34, width: 956, height: 956), xRadius: 214, yRadius: 214).fill()
        NSColor(calibratedRed: 1, green: 0.49, blue: 0.29, alpha: 1).setFill()
        for (index, width) in [480.0, 400, 480, 300].enumerated() {
            NSBezierPath(roundedRect: NSRect(x: 320, y: 710 - Double(index) * 140, width: width, height: 55), xRadius: 24, yRadius: 24).fill()
        }
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 150, y: 620)); arrow.line(to: NSPoint(x: 250, y: 550)); arrow.line(to: NSPoint(x: 150, y: 480)); arrow.close(); arrow.fill()
        image.unlockFocus()
        let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let data = representation.representation(using: .png, properties: [:])!
        let name = "icon_\(size)x\(size)\(factor == 2 ? "@2x" : "").png"
        try data.write(to: directory.appendingPathComponent(name))
    }
}

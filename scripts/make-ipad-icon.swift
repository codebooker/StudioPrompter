import AppKit
import ImageIO
import UniformTypeIdentifiers

// App Store icons are square and opaque. Render the Mac's code-native symbol
// directly into a supported RGB Core Graphics buffer, independent of Retina.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let context = CGContext(data: nil, width: 1024, height: 1024,
    bitsPerComponent: 8, bytesPerRow: 1024 * 4,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.10, green: 0.115, blue: 0.14, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.setFillColor(CGColor(red: 1, green: 0.49, blue: 0.29, alpha: 1))
for (index, width) in [480.0, 400, 480, 300].enumerated() {
    let rect = CGRect(x: 320, y: 710 - Double(index) * 140, width: width, height: 55)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: 24, cornerHeight: 24, transform: nil))
    context.fillPath()
}
context.move(to: CGPoint(x: 150, y: 620))
context.addLine(to: CGPoint(x: 250, y: 550))
context.addLine(to: CGPoint(x: 150, y: 480))
context.closePath()
context.fillPath()
let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
precondition(CGImageDestinationFinalize(destination), "Could not write icon PNG")

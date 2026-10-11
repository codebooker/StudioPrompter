import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

// The existing StudioPrompter mark, with the Mac icon's rounded silhouette.
// Desktop PNG/ICO assets retain transparent corners; App Store assets stay opaque.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let context = CGContext(data: nil, width: 1024, height: 1024,
    bitsPerComponent: 8, bytesPerRow: 1024 * 4,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.setFillColor(CGColor(red: 0.10, green: 0.115, blue: 0.14, alpha: 1))
context.addPath(CGPath(roundedRect: CGRect(x: 34, y: 34, width: 956, height: 956),
    cornerWidth: 214, cornerHeight: 214, transform: nil))
context.fillPath()
context.setFillColor(CGColor(red: 1, green: 0.49, blue: 0.29, alpha: 1))
for (index, width) in [480.0, 400, 480, 300].enumerated() {
    context.addPath(CGPath(roundedRect: CGRect(x: 320, y: 710 - Double(index) * 140, width: width, height: 55),
        cornerWidth: 24, cornerHeight: 24, transform: nil))
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

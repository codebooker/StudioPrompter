import Foundation

/// Screen coordinates use AppKit's bottom-left origin. Stay below menu bars/camera cutouts.
public enum CameraViewGeometry {
    /// `band` is measured relative to a guide at y=0, in logical canvas units.
    /// Keep the whole highlighted area visible, using all available vertical space.
    public static func guideRange(viewportHeight: Double, band: CGRect) -> ClosedRange<Double> {
        guard viewportHeight > 0 else { return 0...0 }
        let top = min(1, max(0, -band.minY / viewportHeight))
        let bottom = min(1, max(top, (viewportHeight - band.maxY) / viewportHeight))
        // An oversized guide has one top-aligned position until the view is enlarged.
        return top...bottom
    }

    public static func frame(screen: CGRect, visible: CGRect, safeTop: CGFloat, size: CGSize? = nil) -> CGRect {
        let notched = safeTop > 0
        let width = min(size?.width ?? (notched ? 580 : 620), max(1, visible.width - 32))
        let height = min(size?.height ?? (notched ? 240 : 260), max(1, visible.height - 32))
        let top = min(visible.maxY, screen.maxY - safeTop) - (notched ? 2 : 8)
        return CGRect(x: visible.midX - width / 2, y: max(visible.minY, top - height), width: width, height: height)
    }
}

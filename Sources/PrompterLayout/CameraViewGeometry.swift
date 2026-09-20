import Foundation

/// Screen coordinates use AppKit's bottom-left origin. Stay below menu bars/camera cutouts.
public enum CameraViewGeometry {
    public static func frame(screen: CGRect, visible: CGRect, safeTop: CGFloat, size: CGSize? = nil) -> CGRect {
        let notched = safeTop > 0
        let width = min(size?.width ?? (notched ? 580 : 620), max(1, visible.width - 32))
        let height = min(size?.height ?? (notched ? 240 : 260), max(1, visible.height - 32))
        let top = min(visible.maxY, screen.maxY - safeTop) - (notched ? 2 : 8)
        return CGRect(x: visible.midX - width / 2, y: max(visible.minY, top - height), width: width, height: height)
    }
}

// MenuBarIcon.swift
// The mark in the menu bar.

import AppKit

/// The app icon's mark, drawn small: a window frame with its right half
/// filled, and three short strokes to its left.
///
/// Drawn here rather than taken from SF Symbols because no symbol carries this
/// shape, and the menu bar is the only place the app is ever seen — it has to
/// be the same mark as the one in `Resources/icon.svg`, at the same
/// proportions, or the two read as two products.
///
/// A template image, never tinted: the only state worth reporting is the
/// missing permission, and that is said in words in the menu rather than in a
/// colour nobody would be able to read.
enum MenuBarIcon {
  /// 17pt, which is what the system items beside it are drawn at, and the
  /// size of the mark rather than of a box around it: the image is the mark's
  /// bounding box exactly, so the menu bar shows 17pt of it. A point of
  /// padding inside would leave Pitatto a size below every one of its
  /// neighbours.
  private static let side: CGFloat = 17

  /// The frame's line, and also the weight of the three strokes — one weight
  /// for the whole mark, the way the app icon is built. 1.3pt at this size is
  /// the weight SF Symbols draws a regular glyph at.
  private static let line: CGFloat = 1.3

  static func image() -> NSImage {
    let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
      // Inset by half the line so the stroke, which straddles the path, stays
      // inside the image rather than being clipped at the edge.
      let frame = NSRect(x: 0.65, y: 0.65, width: 15.7, height: 15.7)
      // 112 of the 648 the app icon's frame is drawn at, kept in proportion.
      let path = NSBezierPath(roundedRect: frame, xRadius: 2.7, yRadius: 2.7)

      NSColor.black.setFill()
      NSColor.black.setStroke()

      // The half runs out to the frame's centre line and the frame is drawn
      // over it, so the two join with no seam. Clipped to the frame so its
      // outer corners follow the frame's own curve.
      NSGraphicsContext.saveGraphicsState()
      path.addClip()
      let middle = frame.midX
      NSRect(x: middle, y: frame.minY, width: frame.maxX - middle, height: frame.height).fill()
      NSGraphicsContext.restoreGraphicsState()

      // The strokes' ends in the app icon's 1024 space, mapped through the
      // frame (188...836 there) so the two stay the same drawing.
      let scale = frame.width / 648
      func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: frame.minX + (x - 188) * scale, y: frame.maxY - (y - 188) * scale)
      }
      let strokes = NSBezierPath()
      for (from, to) in [
        (point(440, 416), point(384, 360)),
        (point(448, 512), point(360, 512)),
        (point(440, 608), point(384, 664)),
      ] {
        strokes.move(to: from)
        strokes.line(to: to)
      }
      strokes.lineWidth = line
      strokes.lineCapStyle = .round
      strokes.stroke()

      path.lineWidth = line
      path.stroke()
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Pitatto"
    return image
  }
}

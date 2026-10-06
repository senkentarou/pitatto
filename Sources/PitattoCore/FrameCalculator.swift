// FrameCalculator.swift
// Work area × width × action → the frame to write. No OS calls: the caller
// hands in the numbers it read from NSScreen.

import CoreGraphics
import Foundation

/// Where a snapped window goes, and how to say it in the two
/// coordinate systems involved.
public enum FrameCalculator {

  /// The frame `action` asks for, in AppKit coordinates.
  ///
  /// Rounded to whole points. The repeat-press judgement compares the frame a
  /// window ended up with against the frame that was asked for, so the
  /// arithmetic has to land on the same number every time — a work area of an
  /// odd width on a scaled display otherwise produces a half point that the
  /// window server rounds one way and this rounds the other.
  public static func frame(for action: SnapAction, size: SnapSize, in workArea: CGRect)
    -> CGRect
  {
    let area = rounded(workArea)
    switch (action, size) {
    case (.maximize, .margin(let points)):
      return area.insetBy(dx: CGFloat(points), dy: CGFloat(points))
    case (.left, .fraction(let numerator, let denominator)):
      let width = (area.width * CGFloat(numerator) / CGFloat(denominator)).rounded()
      return CGRect(x: area.minX, y: area.minY, width: width, height: area.height)
    case (.right, .fraction(let numerator, let denominator)):
      let width = (area.width * CGFloat(numerator) / CGFloat(denominator)).rounded()
      return CGRect(x: area.maxX - width, y: area.minY, width: width, height: area.height)
    case (.top, .fraction(let numerator, let denominator)):
      let height = (area.height * CGFloat(numerator) / CGFloat(denominator)).rounded()
      return CGRect(x: area.minX, y: area.maxY - height, width: area.width, height: height)
    case (.bottom, .fraction(let numerator, let denominator)):
      let height = (area.height * CGFloat(numerator) / CGFloat(denominator)).rounded()
      return CGRect(x: area.minX, y: area.minY, width: area.width, height: height)
    case (.maximize, .fraction), (.left, .margin), (.right, .margin), (.top, .margin),
      (.bottom, .margin):
      preconditionFailure("\(size) is not a step of \(action.rawValue)")
    }
  }

  /// Where a window has to sit to stay against the edge `action` named, given
  /// the size it actually took.
  ///
  /// A window with a minimum width — Terminal below about 240pt — comes out of
  /// the resize wider than asked. Writing the position first and the size
  /// second would leave it overhanging the screen, so the size is read back and
  /// the position recomputed from it.
  ///
  /// Each axis is decided separately, because only one of them is the edge the
  /// action named. A horizontal snap that came out short hangs from the top of
  /// the work area rather than the bottom; a bottom snap (下に寄せる) that came
  /// out tall is the one case that sits on the bottom edge instead. Maximize
  /// (最大化) names no edge and stays centred.
  public static func reseat(_ measured: CGRect, for action: SnapAction, in workArea: CGRect)
    -> CGRect
  {
    let area = rounded(workArea)
    let centred = centredOrigin(of: measured.size, in: area)
    let x: CGFloat
    switch action {
    case .maximize:
      x = centred.x
    case .left, .top, .bottom:
      x = area.minX
    case .right:
      x = area.maxX - measured.width
    }
    let y: CGFloat
    switch action {
    case .maximize:
      y = centred.y
    case .left, .right, .top:
      y = area.maxY - measured.height
    case .bottom:
      y = area.minY
    }
    return CGRect(x: x, y: y, width: measured.width, height: measured.height)
  }

  /// The frame the window will actually end up with, given the smallest it
  /// says it will go.
  ///
  /// A window narrower than its own minimum is not a frame anybody can write:
  /// the app clamps the width and keeps the top-left corner, leaving the window
  /// hanging off the edge it was sent to. Working the clamp out first means one
  /// write that lands, instead of a write, a read and a correction — and the
  /// read is the part that cannot be trusted, because an app is free to apply
  /// a resize long after it was asked.
  ///
  /// `AXMinSize` is how the window says so. Not every window answers; `nil`
  /// means the target stands as asked.
  public static func achievableFrame(
    for action: SnapAction,
    target: CGRect,
    minimumSize: CGSize?,
    in workArea: CGRect
  ) -> CGRect {
    guard let minimumSize else { return target }
    let clamped = CGSize(
      width: max(target.width, minimumSize.width),
      height: max(target.height, minimumSize.height))
    guard clamped != target.size else { return target }
    return reseat(CGRect(origin: target.origin, size: clamped), for: action, in: workArea)
  }

  /// Whether the resize may be written before the move.
  ///
  /// True when the window only gets smaller. It stays on screen while it
  /// shrinks, so it can be moved afterwards — once, and with the size it
  /// actually took rather than the size it was asked for.
  ///
  /// A window that gets bigger has to be moved first. Growing it where it
  /// stands pushes it past the edge it is being sent to, and it sits there
  /// overhanging for as long as the redraw takes; at its old size the target
  /// origin always has room for it, because the target frame fits the work
  /// area and the window is smaller than that.
  public static func resizesBeforeMoving(from current: CGRect, to target: CGRect) -> Bool {
    target.width <= current.width && target.height <= current.height
  }

  /// One write to a window, in AppKit coordinates. A move carries the whole
  /// frame the window is sent to; only its top-left corner is written.
  public enum WriteStep: Equatable, Sendable {
    case resize(CGSize)
    case move(CGRect)
  }

  /// The writes that take a window from `current` to `target`: at most one
  /// resize and one move, in the order that never leaves the window somewhere
  /// it does not fit, and leaving out any write the window would not notice.
  ///
  /// A window that keeps its size — `skipResize`, or the size already matches —
  /// is sent to where a window of that size sits against the edge, not to the
  /// target's own origin. That origin was calculated for a different size, and
  /// sending a wider window there hangs it off the edge until the seat pass
  /// pulls it back, which is one visible hop per press.
  ///
  /// Nothing the window already has is written. A same-value write is not
  /// free: the owning app is told its window changed and lays out again for
  /// it, which under a repeated press is one visible hitch per press even
  /// though nothing moves. Accessibility positions a window by its top-left
  /// corner and keeps that corner fixed across a resize, so "already there" is
  /// judged by that corner.
  ///
  /// - Parameter skipResize: the window is known to be at a size it refused to
  ///   go below, so the size is left alone.
  public static func plan(
    from current: CGRect,
    to target: CGRect,
    for action: SnapAction,
    in workArea: CGRect,
    skipResize: Bool
  ) -> [WriteStep] {
    let resizes = !skipResize && current.size != target.size
    let destination =
      resizes
      ? target
      : reseat(CGRect(origin: target.origin, size: current.size), for: action, in: workArea)
    let moves = destination.minX != current.minX || destination.maxY != current.maxY

    let move: WriteStep? = moves ? .move(destination) : nil
    let resize: WriteStep? = resizes ? .resize(target.size) : nil
    let shrinks = resizesBeforeMoving(from: current, to: target)
    return (shrinks ? [resize, move] : [move, resize]).compactMap { $0 }
  }

  /// The index of the screen `frame` overlaps most, or nil when it overlaps
  /// none of them. A tie goes to the earlier screen, which in the order AppKit
  /// lists them is the one holding the menu bar.
  public static func indexOfScreen(mostOverlapping frame: CGRect, in screens: [CGRect]) -> Int? {
    let areas = screens.map { screen -> CGFloat in
      let intersection = frame.intersection(screen)
      return intersection.isNull ? 0 : intersection.width * intersection.height
    }
    guard let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 else {
      return nil
    }
    return best
  }

  /// AppKit measures from the bottom-left of the primary screen with y growing
  /// up; the Accessibility API measures from its top-left with y growing down.
  /// `primaryScreenHeight` is the height of the screen holding the menu bar,
  /// which is the screen both systems put their origin on.
  public static func axOrigin(of frame: CGRect, primaryScreenHeight: CGFloat) -> CGPoint {
    CGPoint(x: frame.minX, y: primaryScreenHeight - frame.maxY)
  }

  /// The inverse: an Accessibility origin and size back into an AppKit frame.
  public static func appKitFrame(
    axOrigin: CGPoint, size: CGSize, primaryScreenHeight: CGFloat
  ) -> CGRect {
    CGRect(
      x: axOrigin.x,
      y: primaryScreenHeight - axOrigin.y - size.height,
      width: size.width,
      height: size.height)
  }

  /// The middle of `area`, except that a window larger than the area hangs
  /// from its top-left corner — the title bar stays reachable that way.
  private static func centredOrigin(of size: CGSize, in area: CGRect) -> CGPoint {
    CGPoint(
      x: max(area.minX, area.minX + ((area.width - size.width) / 2).rounded()),
      y: min(area.minY + ((area.height - size.height) / 2).rounded(), area.maxY - size.height))
  }

  private static func rounded(_ rect: CGRect) -> CGRect {
    CGRect(
      x: rect.origin.x.rounded(),
      y: rect.origin.y.rounded(),
      width: rect.width.rounded(),
      height: rect.height.rounded())
  }
}

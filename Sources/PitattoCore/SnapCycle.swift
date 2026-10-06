// SnapCycle.swift
// Which width the next press gets.

import CoreGraphics
import Foundation

/// The repeat-press judgement.
///
/// Rectangle's rule, and for the same reason: the only reliable evidence that
/// a press is a repeat is that the window is still exactly where the last press
/// put it. A timer would advance the sequence for someone who paused to read,
/// and reset it for someone who pressed twice slowly.
public enum SnapCycle {

  /// The sizes one shortcut cycles through, in order.
  ///
  /// Maximize (最大化) has its own: margins around a centred window, where an
  /// edge snap (寄せる) has fractions measured from an edge.
  ///
  /// Both lists share one order: the first press's size, then the smallest,
  /// then the one between. The settings columns follow the same order.
  ///
  /// Fixed rather than configurable. A width below the owning app's minimum
  /// window width is clamped to that minimum, and which widths those are
  /// depends on the display and on the app: on a 1440pt work area Chrome holds
  /// at 500pt, so a quarter is already at the edge of what it will take. A
  /// settings screen offering a wider palette would be offering widths it
  /// cannot promise anything about.
  public static func steps(for action: SnapAction) -> [SnapSize] {
    switch action {
    case .maximize: return [.whole, .largeMargin, .smallMargin]
    case .left, .right, .top, .bottom: return [.oneHalf, .oneQuarter, .threeQuarters]
    }
  }

  /// What the last Pitatto shortcut left behind. Held in memory only — a
  /// relaunch starts every window at the front of the sequence, which is also
  /// what happens after the window is touched by hand.
  public struct Placement: Equatable, Sendable {
    public var action: SnapAction
    public var size: SnapSize
    public var processID: Int32
    /// The frame the write asked for. A press can land while the window is
    /// still moving, and what the window was asked to become is better evidence
    /// of "untouched since" than where it happens to be at that instant.
    public var requestedFrame: CGRect
    /// The frame read back once the window came to rest, or nil while it is
    /// still moving. A window with a minimum width lands somewhere other than
    /// it was asked, and comparing against the request alone would make every
    /// press on it a fresh start. A window that has not stopped moving has
    /// told us nothing.
    public var measuredFrame: CGRect?

    public init(
      action: SnapAction, size: SnapSize, processID: Int32, requestedFrame: CGRect,
      measuredFrame: CGRect?
    ) {
      self.action = action
      self.size = size
      self.processID = processID
      self.requestedFrame = requestedFrame
      self.measuredFrame = measuredFrame
    }

    /// The window would not take the size it was given.
    ///
    /// Only a settled frame can say this. Chrome takes the better part of a
    /// second to apply a resize, and reading it too early makes every window
    /// look like it refused — after which the app would stop asking, and the
    /// widths would stop changing.
    public var refusedToShrink: Bool {
      guard let measured = measuredFrame else { return false }
      return measured.width > requestedFrame.width || measured.height > requestedFrame.height
    }

    /// Where a press that has not disturbed the window may find it.
    public func matches(_ frame: CGRect) -> Bool {
      frame == requestedFrame || frame == measuredFrame
    }
  }

  /// Whether the window is known to be sitting at a size it already refused to
  /// go below.
  ///
  /// A minimum size does not move, so a window that would not shrink to one
  /// width will not shrink to a narrower one either. Asking again costs the
  /// owning app a layout pass and a redraw, and a window that redraws blinks —
  /// under a repeated press, once per press. The caller skips the ask and only
  /// re-seats the window.
  ///
  /// Only true while the press continues the last one on the same window: what
  /// is known is about the window that press left behind, and a window that has
  /// been touched since may not be that window at all.
  public static func isAtRefusedMinimum(
    continuing last: Placement?,
    processID: Int32,
    frame: CGRect
  ) -> Bool {
    guard let last, last.processID == processID, last.matches(frame) else { return false }
    return last.refusedToShrink
  }

  /// The size this press should use.
  ///
  /// The window is identified by its owning process and the frame it is sitting
  /// at, not by the window itself: getting a stable window id out of the
  /// Accessibility API needs a private symbol. The case the pair misses — a
  /// second window of the same app, at exactly the frame the last press
  /// produced — continues the sequence rather than restarting it, and since
  /// that window is already at the width the front of the sequence would give
  /// it, continuing is the result a repeat press was asking for anyway.
  /// - Parameter isPartOfSameRun: the press is close enough behind the last one
  ///   to be the same run of presses, so where the window is read to be proves
  ///   nothing. Some apps take a second to apply a resize; some put the window
  ///   back where they want it afterwards. Either way the frame is not evidence
  ///   that the person let go of the key, and the sequence carries on from the
  ///   last press alone.
  public static func size(
    for action: SnapAction,
    continuing last: Placement?,
    processID: Int32,
    frame: CGRect,
    isPartOfSameRun: Bool
  ) -> SnapSize {
    let steps = steps(for: action)
    guard
      let last,
      last.action == action,
      last.processID == processID,
      isPartOfSameRun || last.matches(frame)
    else { return steps[0] }
    return step(after: last.size, in: steps)
  }

  /// The step after `size`, wrapping past the end.
  private static func step(after size: SnapSize, in steps: [SnapSize]) -> SnapSize {
    guard let index = steps.firstIndex(of: size) else { return steps[0] }
    return steps[(index + 1) % steps.count]
  }
}

// SnapCycleTests.swift
// Verifies the repeat-press judgement: a repeated press walks the step
// sequence and wraps, anything that broke the repeat — a different key, a
// different app, a window moved by hand — starts over at the front, and what
// the app remembers about a window that would not shrink or has not stopped
// moving.

import CoreGraphics
import Testing

@testable import PitattoCore

/// A placement the way the session records one. `measured` defaults to
/// `requested`: a settled window that took the size it was given.
private func placement(
  action: SnapAction = .right,
  size: SnapSize,
  processID: Int32,
  requested: CGRect,
  measured: CGRect?? = nil
) -> SnapCycle.Placement {
  SnapCycle.Placement(
    action: action, size: size, processID: processID, requestedFrame: requested,
    measuredFrame: measured ?? requested)
}

@Suite("Snap cycle")
struct SnapCycleTests {

  private let frame = CGRect(x: 1280, y: 0, width: 1280, height: 1562)
  private let pid: Int32 = 501

  private func placed(_ size: SnapSize, action: SnapAction = .right) -> SnapCycle.Placement {
    placement(action: action, size: size, processID: pid, requested: frame)
  }

  private func next(
    _ action: SnapAction = .right,
    continuing last: SnapCycle.Placement?,
    frame: CGRect? = nil,
    pid: Int32? = nil
  ) -> SnapSize {
    SnapCycle.size(
      for: action, continuing: last,
      processID: pid ?? self.pid, frame: frame ?? self.frame, isPartOfSameRun: false)
  }

  @Test("The steps are fixed")
  func theStepsAreFixed() {
    for action in [SnapAction.left, .right, .top, .bottom] {
      #expect(SnapCycle.steps(for: action).map(\.description) == ["1/2", "1/4", "3/4"])
    }
    #expect(SnapCycle.steps(for: .maximize) == [.whole, .largeMargin, .smallMargin])
  }

  @Test("The first press takes the front of the sequence")
  func firstPressTakesTheFrontOfTheSequence() {
    #expect(next(continuing: nil) == .oneHalf)
  }

  @Test("Repeated presses walk the sequence and wrap")
  func repeatedPressesWalkTheSequenceAndWrap() {
    #expect(next(continuing: placed(.oneHalf)) == .oneQuarter)
    #expect(next(continuing: placed(.oneQuarter)) == .threeQuarters)
    #expect(next(continuing: placed(.threeQuarters)) == .oneHalf, "the end wraps to the front")
  }

  @Test("A window moved by hand starts over")
  func aWindowMovedByHandStartsOver() {
    let moved = frame.offsetBy(dx: 12, dy: 0)
    #expect(next(continuing: placed(.oneQuarter), frame: moved) == .oneHalf)
  }

  @Test("The other direction starts over")
  func theOtherDirectionStartsOver() {
    #expect(next(.left, continuing: placed(.oneQuarter)) == .oneHalf)
  }

  @Test("Another app starts over")
  func anotherAppStartsOver() {
    #expect(next(continuing: placed(.oneQuarter), pid: 999) == .oneHalf)
  }

  @Test("Maximize goes whole, then the large margin, then the small one, and wraps")
  func maximizeGoesToTheSmallestWindowThenBetweenAndWraps() {
    #expect(next(.maximize, continuing: nil) == .whole)
    #expect(next(.maximize, continuing: placed(.whole, action: .maximize)) == .largeMargin)
    #expect(next(.maximize, continuing: placed(.largeMargin, action: .maximize)) == .smallMargin)
    #expect(next(.maximize, continuing: placed(.smallMargin, action: .maximize)) == .whole)
  }
}

// Asking a window that will not shrink for a narrower size again makes it lay
// out and redraw for nothing, which is visible as the window blinking once per
// press.
@Suite("Refused minimum")
struct RefusedMinimumTests {

  private let workArea = CGRect(x: 0, y: 0, width: 1440, height: 875)
  private let pid: Int32 = 2000
  /// Flush right at the 1100pt the window would not go below.
  private let atMinimum = CGRect(x: 340, y: 0, width: 1100, height: 875)

  private func placed(requested: CGFloat) -> SnapCycle.Placement {
    placement(
      size: .oneHalf, processID: pid,
      requested: CGRect(x: 1440 - requested, y: 0, width: requested, height: 875),
      measured: atMinimum)
  }

  @Test("A window that took the size it was given is not at a minimum")
  func aWindowThatTookTheSizeItWasGivenIsNotAtAMinimum() {
    let placed = placed(requested: 1100)
    #expect(!placed.refusedToShrink)
    #expect(!SnapCycle.isAtRefusedMinimum(continuing: placed, processID: pid, frame: atMinimum))
  }

  @Test("A window that refused is remembered")
  func aWindowThatRefusedIsRemembered() {
    let placed = placed(requested: 720)
    #expect(placed.refusedToShrink)
    #expect(SnapCycle.isAtRefusedMinimum(continuing: placed, processID: pid, frame: atMinimum))
  }

  /// The knowledge is about the window that press left behind. Moved by hand,
  /// or another app in front, and it no longer applies.
  @Test("The knowledge does not carry to another window")
  func theKnowledgeDoesNotCarryToAnotherWindow() {
    let placed = placed(requested: 720)
    #expect(
      !SnapCycle.isAtRefusedMinimum(
        continuing: placed, processID: pid, frame: atMinimum.offsetBy(dx: 20, dy: 0)))
    #expect(!SnapCycle.isAtRefusedMinimum(continuing: placed, processID: 999, frame: atMinimum))
    #expect(!SnapCycle.isAtRefusedMinimum(continuing: nil, processID: pid, frame: atMinimum))
  }

  /// Growing is still tried: maximize and the wrap back to the front of the
  /// sequence both ask for a size the window has never refused.
  @Test("Growing is still attempted")
  func growingIsStillAttempted() {
    let maximize = FrameCalculator.frame(for: .maximize, size: .whole, in: workArea)
    #expect(!FrameCalculator.resizesBeforeMoving(from: atMinimum, to: maximize))
  }
}

// An app that animates its resize is somewhere between the two frames when the
// next press arrives, and comparing against the measured frame alone sent the
// sequence back to its front on every other press.
@Suite("Settling window")
struct SettlingWindowTests {

  private let pid: Int32 = 92527

  /// A window told to be 360 wide that came to rest at its 500pt minimum: the
  /// press that put it there recorded both frames.
  private var placed: SnapCycle.Placement {
    placement(
      size: .oneQuarter, processID: pid,
      requested: CGRect(x: 1080, y: 0, width: 360, height: 875),
      measured: CGRect(x: 940, y: 0, width: 500, height: 875))
  }

  @Test("A window found where it came to rest continues")
  func aWindowFoundWhereItCameToRestContinues() {
    let size = SnapCycle.size(
      for: .right, continuing: placed, processID: pid,
      frame: CGRect(x: 940, y: 0, width: 500, height: 875), isPartOfSameRun: false)
    #expect(size == .threeQuarters)
  }

  /// The next press arrives before the seat pass has run, so the window is
  /// still at the frame it was asked for rather than the one it settled on.
  @Test("A window found where it was asked to be continues")
  func aWindowFoundWhereItWasAskedToBeContinues() {
    let size = SnapCycle.size(
      for: .right, continuing: placed, processID: pid,
      frame: CGRect(x: 1080, y: 0, width: 360, height: 875), isPartOfSameRun: false)
    #expect(size == .threeQuarters)
  }

  @Test("A window found anywhere else starts over")
  func aWindowFoundAnywhereElseStartsOver() {
    let size = SnapCycle.size(
      for: .right, continuing: placed, processID: pid,
      frame: CGRect(x: 720, y: 0, width: 720, height: 875), isPartOfSameRun: false)
    #expect(size == .oneHalf)
  }
}

// Chrome takes over a second to apply a resize and answers with a different
// size every time it is asked on the way there, so a press that lands in that
// gap has to be read as a repeat on the strength of the last press alone.
@Suite("Same run")
struct SameRunTests {

  private let pid: Int32 = 92527
  private let moved = CGRect(x: 0, y: 0, width: 960, height: 875)

  private var pending: SnapCycle.Placement {
    placement(
      size: .oneQuarter, processID: pid,
      requested: CGRect(x: 1080, y: 0, width: 360, height: 875), measured: .some(nil))
  }

  @Test("A press landing before the window stops moving still steps")
  func aPressLandingBeforeTheWindowStopsMovingStillSteps() {
    let size = SnapCycle.size(
      for: .right, continuing: pending, processID: pid, frame: moved, isPartOfSameRun: true)
    #expect(size == .threeQuarters)
  }

  /// The same read once the window has stopped: it is nowhere near either
  /// frame, so it was moved by hand and the sequence starts over.
  @Test("The same read after the window stops starts over")
  func theSameReadAfterTheWindowStopsStartsOver() {
    let size = SnapCycle.size(
      for: .right, continuing: pending, processID: pid, frame: moved, isPartOfSameRun: false)
    #expect(size == .oneHalf)
  }

  /// Believing a refusal read off a moving window made the app stop asking,
  /// and the widths stopped changing. A placement with no measured frame has
  /// nothing to compare, so it cannot say the window refused.
  @Test("A refusal cannot be read off a window that has not come to rest")
  func anUnsettledPlacementNeverReportsARefusal() {
    #expect(!pending.refusedToShrink)
    #expect(
      !SnapCycle.isAtRefusedMinimum(
        continuing: pending, processID: pid, frame: pending.requestedFrame))

    var settled = pending
    settled.measuredFrame = CGRect(x: 940, y: 0, width: 500, height: 875)
    #expect(settled.refusedToShrink)
  }

  @Test("A different key while the window is still moving is not a repeat")
  func anotherDirectionStillStartsOver() {
    let size = SnapCycle.size(
      for: .left, continuing: pending, processID: pid, frame: moved, isPartOfSameRun: true)
    #expect(size == .oneHalf)
  }
}

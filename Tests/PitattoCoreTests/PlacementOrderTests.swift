// PlacementOrderTests.swift
// Verifies the rule that decides whether the resize is written before the move,
// and the frame worked out for a window that will not go below a size it
// reports. Getting the order backwards leaves the window overhanging the screen
// for the length of one redraw, which is visible as the window blinking out
// and back.

import CoreGraphics
import Testing

@testable import PitattoCore

private let workArea = CGRect(x: 0, y: 0, width: 1440, height: 875)

@Suite("Placement order")
struct PlacementOrderTests {

  /// Right half → right quarter. Moving first would put a 720pt window at
  /// x=1080, 360pt past the right edge.
  @Test("Shrinking resizes first")
  func shrinkingResizesFirst() {
    let current = CGRect(x: 720, y: 0, width: 720, height: 875)
    let target = FrameCalculator.frame(for: .right, size: .oneQuarter, in: workArea)
    #expect(FrameCalculator.resizesBeforeMoving(from: current, to: target))
  }

  /// Right quarter → right three quarters. Resizing first would push the
  /// window's right edge to 1440 + 720.
  @Test("Growing moves first")
  func growingMovesFirst() {
    let current = CGRect(x: 1080, y: 0, width: 360, height: 875)
    let target = FrameCalculator.frame(for: .right, size: .threeQuarters, in: workArea)
    #expect(!FrameCalculator.resizesBeforeMoving(from: current, to: target))
  }

  /// The window has to be at the target's left edge before it can widen into it.
  @Test("Wider but shorter counts as growing, so the move goes first")
  func widerButShorterMovesFirst() {
    let current = CGRect(x: 900, y: 0, width: 300, height: 900)
    let target = CGRect(x: 720, y: 0, width: 720, height: 875)
    #expect(!FrameCalculator.resizesBeforeMoving(from: current, to: target))
  }

  @Test("A minimum-width window is seated with the width it took, so the move is one it can hold")
  func aMinimumWidthWindowIsSeatedWithTheWidthItTook() {
    let target = FrameCalculator.frame(for: .right, size: .oneHalf, in: workArea)
    let achieved = CGSize(width: 1100, height: 875)
    let seated = FrameCalculator.reseat(
      CGRect(origin: target.origin, size: achieved), for: .right, in: workArea)
    #expect(seated.minX == 340)
    #expect(seated.maxX == workArea.maxX)
    #expect(workArea.contains(seated))
  }
}

// The writes a press turns into. Getting them wrong is visible: a window moved
// before it shrinks overhangs the screen for one redraw, and a write the window
// already has makes the owning app lay out again for nothing.
@Suite("Write plan")
struct WritePlanTests {

  private func plan(
    from current: CGRect, to target: CGRect, for action: SnapAction = .right,
    skipResize: Bool = false
  ) -> [FrameCalculator.WriteStep] {
    FrameCalculator.plan(
      from: current, to: target, for: action, in: workArea, skipResize: skipResize)
  }

  @Test("Shrinking is a resize, then a move to the target")
  func shrinkingResizesThenMoves() {
    let current = CGRect(x: 720, y: 0, width: 720, height: 875)
    let target = FrameCalculator.frame(for: .right, size: .oneQuarter, in: workArea)
    #expect(plan(from: current, to: target) == [.resize(target.size), .move(target)])
  }

  @Test("Growing is a move to the target, then a resize")
  func growingMovesThenResizes() {
    let current = CGRect(x: 1080, y: 0, width: 360, height: 875)
    let target = FrameCalculator.frame(for: .right, size: .threeQuarters, in: workArea)
    #expect(plan(from: current, to: target) == [.move(target), .resize(target.size)])
  }

  @Test("A window already at the target is asked for nothing")
  func aWindowAlreadyThereIsLeftAlone() {
    let target = FrameCalculator.frame(for: .right, size: .oneHalf, in: workArea)
    #expect(plan(from: target, to: target) == [])
  }

  @Test("The same size somewhere else is one move")
  func theSameSizeElsewhereIsOneMove() {
    let current = CGRect(x: 0, y: 0, width: 720, height: 875)
    let target = FrameCalculator.frame(for: .right, size: .oneHalf, in: workArea)
    #expect(plan(from: current, to: target) == [.move(target)])
  }

  /// Chrome holds at 500pt and is already flush right. A narrower step is
  /// skipped, and the window is not sent to the narrower frame's origin, where
  /// it would hang 140pt off the edge until the seat pass pulled it back.
  @Test("A window at a refused minimum is not resized, and is seated for its own size")
  func aRefusedMinimumIsSeatedNotResized() {
    let atMinimum = CGRect(x: 940, y: 0, width: 500, height: 875)
    let target = FrameCalculator.frame(for: .right, size: .oneQuarter, in: workArea)
    #expect(plan(from: atMinimum, to: target, skipResize: true) == [])

    let nudged = atMinimum.offsetBy(dx: -40, dy: 0)
    #expect(plan(from: nudged, to: target, skipResize: true) == [.move(atMinimum)])
  }

  /// Accessibility keeps the top-left corner fixed across a resize, so that
  /// corner — not AppKit's bottom-left origin — decides whether a move is due.
  @Test("A window whose top-left corner is already right only resizes")
  func aWindowWithTheRightTopLeftCornerOnlyResizes() {
    let target = FrameCalculator.frame(for: .top, size: .oneHalf, in: workArea)
    let taller = CGRect(x: 0, y: 0, width: 1440, height: 875)
    #expect(plan(from: taller, to: target, for: .top) == [.resize(target.size)])
  }
}

// Writing the frame the size asks for and correcting afterwards means reading
// a size back from an app that may not have applied the resize yet, which is
// the read that cannot be trusted. The achievable frame is worked out first.
@Suite("Achievable frame")
struct AchievableFrameTests {

  /// Chrome will not go below 500pt wide, so the right quarter is 500pt wide
  /// and flush right rather than 360pt hanging 140pt off the screen.
  @Test("A window wider than the fraction is seated at its minimum")
  func aWindowWiderThanTheFractionIsSeatedAtItsMinimum() {
    let target = FrameCalculator.frame(for: .right, size: .oneQuarter, in: workArea)
    let achievable = FrameCalculator.achievableFrame(
      for: .right, target: target,
      minimumSize: CGSize(width: 500, height: 400), in: workArea)
    #expect(achievable == CGRect(x: 940, y: 0, width: 500, height: 875))
    #expect(achievable.maxX == workArea.maxX)
  }

  @Test("The left edge is unmoved by a minimum")
  func theLeftEdgeIsUnmovedByAMinimum() {
    let target = FrameCalculator.frame(for: .left, size: .oneQuarter, in: workArea)
    let achievable = FrameCalculator.achievableFrame(
      for: .left, target: target,
      minimumSize: CGSize(width: 500, height: 400), in: workArea)
    #expect(achievable == CGRect(x: 0, y: 0, width: 500, height: 875))
  }

  @Test("A minimum the size already clears changes nothing")
  func aFractionAboveTheMinimumIsLeftAlone() {
    let target = FrameCalculator.frame(for: .right, size: .oneHalf, in: workArea)
    let achievable = FrameCalculator.achievableFrame(
      for: .right, target: target,
      minimumSize: CGSize(width: 500, height: 400), in: workArea)
    #expect(achievable == target)
  }

  @Test("A window that does not report a minimum gets the frame as calculated")
  func aWindowThatSaysNothingIsAskedForTheFraction() {
    let target = FrameCalculator.frame(for: .right, size: .oneQuarter, in: workArea)
    let achievable = FrameCalculator.achievableFrame(
      for: .right, target: target, minimumSize: nil, in: workArea)
    #expect(achievable == target)
  }

  /// A window that will not go as short as a quarter of the height still ends
  /// up on the bottom edge when that is the edge the bottom snap named.
  @Test("A minimum height is seated on the bottom edge")
  func aMinimumHeightIsSeatedOnTheBottomEdge() {
    let target = FrameCalculator.frame(for: .bottom, size: .oneQuarter, in: workArea)
    let achievable = FrameCalculator.achievableFrame(
      for: .bottom, target: target,
      minimumSize: CGSize(width: 400, height: 600), in: workArea)
    #expect(achievable == CGRect(x: 0, y: 0, width: 1440, height: 600))
    #expect(achievable.minY == workArea.minY)
  }

  /// A minimum height taller than the work area hangs the window from the top,
  /// which is where `reseat` puts a horizontal snap.
  @Test("A minimum height taller than the area hangs from the top")
  func aMinimumHeightHangsFromTheTop() {
    let target = FrameCalculator.frame(for: .left, size: .oneHalf, in: workArea)
    let achievable = FrameCalculator.achievableFrame(
      for: .left, target: target,
      minimumSize: CGSize(width: 400, height: 1000), in: workArea)
    #expect(achievable.height == 1000)
    #expect(achievable.maxY == workArea.maxY)
  }
}

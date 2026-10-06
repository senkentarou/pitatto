// SnapSessionTests.swift
// Verifies the press pipeline end to end, without a window: which presses are
// written, which are held while the window is still moving, what a held press
// becomes once the window settles, and what every step leaves behind for the
// repeat judgement.

import CoreGraphics
import Testing

@testable import PitattoCore

@Suite("Snap session")
struct SnapSessionTests {

  private let workArea = CGRect(x: 0, y: 0, width: 1440, height: 875)
  private let pid: Int32 = 1
  private let start = ContinuousClock.now

  private let rightHalf = CGRect(x: 720, y: 0, width: 720, height: 875)
  private let rightQuarter = CGRect(x: 1080, y: 0, width: 360, height: 875)
  private let rightThreeQuarters = CGRect(x: 360, y: 0, width: 1080, height: 875)
  /// Where a window that will not go below 500pt wide comes to rest after
  /// being asked for the right quarter.
  private let atMinimum = CGRect(x: 940, y: 0, width: 500, height: 875)
  /// Somewhere a snap never puts a window: the hand moved it.
  private let moved = CGRect(x: 5, y: 5, width: 800, height: 600)

  private func press(
    _ action: SnapAction = .right,
    size: SnapSize? = nil,
    processID: Int32? = nil,
    current: CGRect,
    minimumSize: CGSize? = nil,
    after offset: Duration = .zero
  ) -> SnapSession.Press {
    SnapSession.Press(
      action: action, size: size, processID: processID ?? pid, current: current,
      workArea: workArea, minimumSize: minimumSize, now: start.advanced(by: offset))
  }

  /// A session that has written one right-half snap and is waiting for the
  /// window to settle.
  private func sessionWriting() -> (SnapSession, SnapSession.Plan) {
    var session = SnapSession()
    let effect = session.press(press(current: moved))
    guard case .write(let plan, false) = effect else {
      Issue.record("expected a write, got \(effect)")
      return (session, effect.plan)
    }
    session.didWrite(plan, wrote: true, current: moved)
    return (session, plan)
  }

  @Test("One press on a window that settles at once: write, record, and step next time")
  func onePressWritesAndRecords() {
    let (started, plan) = sessionWriting()
    var session = started
    #expect(plan.size == .oneHalf)
    #expect(plan.target == rightHalf)
    #expect(session.isSettling)
    #expect(session.lastPlacement?.measuredFrame == nil)

    #expect(session.settled(plan, measured: rightHalf) == .none)
    #expect(!session.isSettling)
    #expect(session.lastPlacement?.measuredFrame == rightHalf)
    #expect(session.lastPlacement?.refusedToShrink == false)

    let next = session.press(press(current: rightHalf, after: .seconds(2)))
    #expect(next.plan.size == .oneQuarter)
  }

  @Test("Three presses on a slow window are one write, two holds and one release to 3/4")
  func threePressesAreOneWriteAndOneRelease() {
    let (started, first) = sessionWriting()
    var session = started

    let second = session.press(press(current: moved, after: .milliseconds(100)))
    #expect(second == .hold(second.plan))
    #expect(second.plan.size == .oneQuarter)
    #expect(session.pending == second.plan)

    let third = session.press(press(current: moved, after: .milliseconds(200)))
    #expect(third == .hold(third.plan))
    #expect(third.plan.size == .threeQuarters)
    #expect(session.pending == third.plan, "only the latest held press is kept")

    #expect(session.settled(first, measured: rightHalf) == .apply(third.plan))
    #expect(session.pending == nil)
    #expect(
      session.release(third.plan, current: rightHalf) == .write(third.plan, skipResize: false))
    session.didWrite(third.plan, wrote: true, current: rightHalf)
    #expect(session.lastPlacement?.size == .threeQuarters)
    #expect(session.lastPlacement?.requestedFrame == rightThreeQuarters)
  }

  @Test("A fourth press wraps to the front, and the release finds the window already there")
  func aWrappedReleaseLeavesTheWindowAlone() {
    let (started, first) = sessionWriting()
    var session = started
    for offset in [100, 200, 300] {
      _ = session.press(press(current: moved, after: .milliseconds(offset)))
    }
    #expect(session.pending?.size == .oneHalf)

    guard case .apply(let fourth) = session.settled(first, measured: rightHalf) else {
      Issue.record("expected the held press back")
      return
    }
    #expect(session.release(fourth, current: rightHalf) == .leave(fourth))
    #expect(session.lastPlacement?.size == .oneHalf)
    #expect(session.lastPlacement?.measuredFrame == rightHalf)
    #expect(!session.isSettling)
  }

  @Test("A window at a refused minimum is not asked to shrink again, but growing is tried")
  func aRefusedMinimumSkipsTheResize() {
    var session = SnapSession()
    let quarter = session.press(press(size: .oneQuarter, current: rightHalf))
    #expect(quarter == .write(quarter.plan, skipResize: false))
    session.didWrite(quarter.plan, wrote: true, current: rightHalf)
    _ = session.settled(quarter.plan, measured: atMinimum)
    #expect(session.lastPlacement?.refusedToShrink == true)

    let again = session.press(press(size: .oneQuarter, current: atMinimum, after: .seconds(2)))
    #expect(again == .write(again.plan, skipResize: true))
    session.didWrite(again.plan, wrote: false, current: atMinimum)
    #expect(!session.isSettling, "nothing was written, so there is nothing to wait for")
    #expect(session.lastPlacement?.measuredFrame == atMinimum)
    #expect(session.lastPlacement?.refusedToShrink == true)

    let grow = session.press(press(current: atMinimum, after: .seconds(4)))
    #expect(grow.plan.size == .threeQuarters)
    #expect(grow == .write(grow.plan, skipResize: false))
  }

  /// The release reads the window straight after the seat pass wrote to it. An
  /// app that applies writes late still reports the pre-seat frame, which
  /// matches neither frame the session knows, so the skip is lost for that one
  /// press. Pinned as it is today.
  @Test("A release that reads a stale frame after the seat pass asks for the resize again")
  func aStaleReadAfterSeatingLosesTheSkip() {
    var session = SnapSession()
    let quarter = session.press(press(size: .oneQuarter, current: rightHalf))
    session.didWrite(quarter.plan, wrote: true, current: rightHalf)
    let held = session.press(
      press(size: .oneQuarter, current: rightHalf, after: .milliseconds(100)))
    #expect(held == .hold(held.plan))

    #expect(session.settled(quarter.plan, measured: atMinimum) == .apply(held.plan))
    let stale = CGRect(x: 1080, y: 0, width: 500, height: 875)
    #expect(session.release(held.plan, current: stale) == .write(held.plan, skipResize: false))
  }

  @Test("A refusal carries across actions: the minimum belongs to the window, not the edge")
  func aRefusalCarriesAcrossActions() {
    var session = SnapSession()
    let quarter = session.press(press(size: .oneQuarter, current: rightHalf))
    session.didWrite(quarter.plan, wrote: true, current: rightHalf)
    _ = session.settled(quarter.plan, measured: atMinimum)

    let left = session.press(
      press(.left, size: .oneQuarter, current: atMinimum, after: .seconds(2)))
    #expect(left == .write(left.plan, skipResize: true))
  }

  @Test("Inside the grace period a moved window still steps; past it the sequence starts over")
  func theGracePeriodDecidesWhatAMovedWindowMeans() {
    var inside = SnapSession()
    let plan = inside.press(press(current: moved)).plan
    inside.didWrite(plan, wrote: true, current: moved)
    _ = inside.settled(plan, measured: rightHalf)
    #expect(
      inside.press(press(current: moved, after: .milliseconds(1400))).plan.size == .oneQuarter)

    var outside = SnapSession()
    let other = outside.press(press(current: moved)).plan
    outside.didWrite(other, wrote: true, current: moved)
    _ = outside.settled(other, measured: rightHalf)
    #expect(outside.press(press(current: moved, after: .milliseconds(1600))).plan.size == .oneHalf)
  }

  @Test("A held press restarts the grace period, so a run of presses is measured from its last")
  func aHeldPressRestartsTheGracePeriod() {
    let (started, first) = sessionWriting()
    var session = started
    let held = session.press(press(current: moved, after: .milliseconds(1000)))
    #expect(held == .hold(held.plan))

    #expect(session.settled(first, measured: rightHalf) == .apply(held.plan))
    let released = session.release(held.plan, current: rightHalf)
    #expect(released == .write(held.plan, skipResize: false))
    session.didWrite(held.plan, wrote: true, current: rightHalf)
    _ = session.settled(held.plan, measured: rightQuarter)

    // 1400ms after the held press, 2400ms after the first: still the same run.
    let next = session.press(press(current: moved, after: .milliseconds(2400)))
    #expect(next.plan.size == .threeQuarters)
  }

  @Test("A different action while the window moves is held, and starts its own sequence")
  func anotherActionWhileMovingStartsItsOwnSequence() {
    let (started, first) = sessionWriting()
    var session = started
    let left = session.press(press(.left, current: moved, after: .milliseconds(100)))
    #expect(left == .hold(left.plan))
    #expect(left.plan.size == .oneHalf)
    #expect(session.lastPlacement?.action == .left)

    #expect(session.settled(first, measured: rightHalf) == .apply(left.plan))
    #expect(session.release(left.plan, current: rightHalf) == .write(left.plan, skipResize: false))
  }

  @Test("A press on another app's window waits behind the first and is written for that app")
  func anotherAppsPressWaitsAndIsWritten() {
    var session = SnapSession()
    let quarter = session.press(press(size: .oneQuarter, current: rightHalf))
    session.didWrite(quarter.plan, wrote: true, current: rightHalf)
    let other = session.press(press(processID: 2, current: moved, after: .milliseconds(100)))
    #expect(other == .hold(other.plan))
    #expect(other.plan.size == .oneHalf, "another app's window starts its own sequence")

    #expect(session.settled(quarter.plan, measured: atMinimum) == .apply(other.plan))
    #expect(session.lastPlacement?.refusedToShrink == true)
    #expect(
      session.release(other.plan, current: moved) == .write(other.plan, skipResize: false),
      "the first window's refusal does not carry to another process")
  }

  @Test("Only one press is held: a later press on any window replaces an earlier one")
  func onlyTheLatestPressIsHeld() {
    var session = sessionWriting().0
    _ = session.press(press(processID: 2, current: moved, after: .milliseconds(100)))
    let later = session.press(press(current: moved, after: .milliseconds(200)))
    #expect(session.pending == later.plan)
    #expect(session.pending?.processID == pid)
  }

  @Test("A window that would not say where it settled leaves the last placement unmeasured")
  func anUnreadableWindowLeavesThePlacementUnmeasured() {
    let (started, first) = sessionWriting()
    var session = started
    let held = session.press(press(current: moved, after: .milliseconds(100)))

    #expect(session.settled(first, measured: nil) == .apply(held.plan))
    #expect(!session.isSettling)
    #expect(session.lastPlacement?.measuredFrame == nil)
    #expect(session.lastPlacement?.refusedToShrink == false)
  }

  @Test("While the window settles, a press is held however long since the last one")
  func aSettlingWindowHoldsRegardlessOfTheGracePeriod() {
    var session = sessionWriting().0
    let late = session.press(press(current: moved, after: .milliseconds(1600)))
    #expect(late == .hold(late.plan))
    #expect(late.plan.size == .oneQuarter)
  }
}

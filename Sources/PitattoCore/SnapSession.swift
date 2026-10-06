// SnapSession.swift
// The repeat-press pipeline as a value: what one press does, given what the
// last one left behind and whether its window has stopped moving. No OS calls:
// the app reads the window and the clock, hands the numbers in, and performs
// what comes back.

import CoreGraphics
import Foundation

public struct SnapSession: Sendable {

  /// What the app read for one press: the window's process and frame, the work
  /// area it is on, the smallest size it reports, and the time.
  public struct Press: Sendable {
    public var action: SnapAction
    /// nil is the cycling form: the size is the next step of the sequence.
    public var size: SnapSize?
    public var processID: Int32
    public var current: CGRect
    public var workArea: CGRect
    public var minimumSize: CGSize?
    public var now: ContinuousClock.Instant

    public init(
      action: SnapAction,
      size: SnapSize?,
      processID: Int32,
      current: CGRect,
      workArea: CGRect,
      minimumSize: CGSize?,
      now: ContinuousClock.Instant
    ) {
      self.action = action
      self.size = size
      self.processID = processID
      self.current = current
      self.workArea = workArea
      self.minimumSize = minimumSize
      self.now = now
    }
  }

  /// One write the session decided on: enough to perform it, and to report
  /// back what the window did with it.
  public struct Plan: Equatable, Sendable {
    public var action: SnapAction
    public var size: SnapSize
    public var processID: Int32
    public var target: CGRect
    public var workArea: CGRect

    public init(
      action: SnapAction, size: SnapSize, processID: Int32, target: CGRect, workArea: CGRect
    ) {
      self.action = action
      self.size = size
      self.processID = processID
      self.target = target
      self.workArea = workArea
    }
  }

  /// What a press turns into.
  public enum Effect: Equatable, Sendable {
    /// The window is still responding to the last write. Nothing is written;
    /// the plan waits for `settled` and replaces whatever was waiting before.
    ///
    /// This is what makes a run of presses work. Chrome takes about a second
    /// to apply a resize, so four presses written straight through are four
    /// requests queued in another process, applied late and in whatever order
    /// they come out — a window jumping between sizes nobody asked for. Held
    /// back, the same four presses are one write, to the width the last press
    /// landed on. The steps in between are skipped rather than shown, which is
    /// the only honest option when the window cannot keep up with the keyboard.
    case hold(Plan)
    /// The window is already exactly there — the whole sequence is one width,
    /// or the window was put there by hand. Writing the same geometry again
    /// makes the window repaint for nothing, which is visible as a flicker
    /// under a repeated press.
    case leave(Plan)
    /// Written now. `skipResize` when the window is known to sit at a size it
    /// refused to go below: it will refuse anything narrower, and the ask
    /// alone makes it redraw. Only shrinking is skipped — the wrap back to the
    /// front of the sequence, and maximize, still have to be tried.
    case write(Plan, skipResize: Bool)

    public var plan: Plan {
      switch self {
      case .hold(let plan), .leave(let plan), .write(let plan, _): return plan
      }
    }
  }

  /// What `settled` hands back: the press that was held while the window
  /// moved, if there was one.
  public enum Release: Equatable, Sendable {
    case none
    case apply(Plan)
  }

  /// What the last press left behind, for the repeat judgement. Memory only:
  /// after a relaunch every window starts at the front of the sequence, which
  /// is also what happens once a window is touched by hand.
  public private(set) var lastPlacement: SnapCycle.Placement?

  /// True from the moment a press writes until its window is confirmed at rest.
  /// While it holds, the next press continues the sequence without asking where
  /// the window is: it is somewhere between two frames and would answer with a
  /// number that matches neither.
  public private(set) var isSettling = false

  /// The press that arrived while the window was still moving. Only the latest
  /// is kept — the ones before it were overtaken before anything was written.
  /// One slot for every window: a press on another window while this one
  /// settles waits behind it, and is dropped if a third press arrives first.
  public private(set) var pending: Plan?

  /// When the last press arrived, held or not, for the same-run judgement.
  public private(set) var lastPressAt: ContinuousClock.Instant?

  /// How long after a press the next one still counts as the same run.
  ///
  /// Nobody reaches for the mouse, moves a window and comes back to the
  /// keyboard inside a second and a half, so a press this soon after the last
  /// is a repeat whatever the window says about itself. Without it, an app that
  /// puts its own window back after every write sends the sequence to its
  /// front on every press, and the widths never advance.
  public let sameRunGrace: Duration

  public init(sameRunGrace: Duration = .milliseconds(1500)) {
    self.sameRunGrace = sameRunGrace
  }

  /// One press of one shortcut.
  ///
  /// A sized command names the width it wants; a cycling one asks where the
  /// last press left off. Either way the placement is recorded the same, so a
  /// sized left 1/4 followed by the cycling key steps on to 3/4.
  public mutating func press(_ press: Press) -> Effect {
    let size =
      press.size
      ?? SnapCycle.size(
        for: press.action,
        continuing: lastPlacement,
        processID: press.processID,
        frame: press.current,
        isPartOfSameRun: isSettling || isWithinSameRun(at: press.now))
    let target = FrameCalculator.achievableFrame(
      for: press.action,
      target: FrameCalculator.frame(for: press.action, size: size, in: press.workArea),
      minimumSize: press.minimumSize,
      in: press.workArea)
    lastPressAt = press.now
    let plan = Plan(
      action: press.action, size: size, processID: press.processID, target: target,
      workArea: press.workArea)

    guard !isSettling else {
      pending = plan
      // Recorded even though nothing is written: the next press has to see
      // this one to carry the sequence forward.
      lastPlacement = placement(of: plan, measured: nil)
      return .hold(plan)
    }
    return decide(plan, current: press.current)
  }

  /// What the window did with a `.write`: `wrote` is false when nothing had
  /// to be written after all, in which case the window stays at `current` and
  /// nothing is going to be reported.
  public mutating func didWrite(_ plan: Plan, wrote: Bool, current: CGRect) {
    guard wrote else {
      lastPlacement = placement(of: plan, measured: current)
      return
    }
    // The target stands in for the measured frame until the window has stopped
    // moving. It has to: the size cannot be read yet, and a press that lands
    // before the window settles needs something to compare against.
    lastPlacement = placement(of: plan, measured: nil)
    isSettling = true
  }

  /// The window has come to rest after `plan` and been seated; `measured` is
  /// where it is now, or nil when it would not say. Returns the press that
  /// was held in the meantime, for the app to read the window again and
  /// `release`.
  public mutating func settled(_ plan: Plan, measured: CGRect?) -> Release {
    if let measured {
      lastPlacement = placement(of: plan, measured: measured)
    }
    isSettling = false
    guard let next = pending else { return .none }
    pending = nil
    return .apply(next)
  }

  /// The held press, now that the window it is for can be read again.
  public mutating func release(_ plan: Plan, current: CGRect) -> Effect {
    decide(plan, current: current)
  }

  private mutating func decide(_ plan: Plan, current: CGRect) -> Effect {
    guard current != plan.target else {
      lastPlacement = placement(of: plan, measured: current)
      return .leave(plan)
    }
    let skipResize =
      SnapCycle.isAtRefusedMinimum(
        continuing: lastPlacement, processID: plan.processID, frame: current)
      && FrameCalculator.resizesBeforeMoving(from: current, to: plan.target)
    return .write(plan, skipResize: skipResize)
  }

  private func isWithinSameRun(at now: ContinuousClock.Instant) -> Bool {
    guard let lastPressAt else { return false }
    return lastPressAt.duration(to: now) < sameRunGrace
  }

  private func placement(of plan: Plan, measured: CGRect?) -> SnapCycle.Placement {
    SnapCycle.Placement(
      action: plan.action, size: plan.size, processID: plan.processID,
      requestedFrame: plan.target, measuredFrame: measured)
  }
}

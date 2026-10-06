// WindowSettle.swift
// Waiting for a window to actually stop moving.

import AppKit
import ApplicationServices

/// Waits until the window has finished responding to a frame write.
///
/// `AXUIElementSetAttributeValue` returns as soon as the other app has taken
/// the message, not when its window has changed. What the app does next is its
/// own business: AppKit usually resizes inside that round trip, Chrome hands
/// the request to another process and gets to it the better part of a second
/// later, changing the window more than once on the way.
///
/// Polling cannot tell those apart. An app that has not started yet answers
/// with exactly the same frame as one that has finished, so two equal reads
/// mean nothing.
///
/// So the app is not asked; it is listened to. macOS posts a notification when
/// a window really moves or resizes, and this waits for those to stop arriving.
@MainActor
enum WindowSettle {
  /// Starts listening to `window`. Called before the frame is written, never
  /// after.
  ///
  /// Before, because an app applies the frame change inside the write call
  /// itself and posts its move and resize while that call is still running. An
  /// observer installed afterwards has nothing left to hear: it never records
  /// an event, so every wait runs to `timeout` and every press held behind it
  /// waits that long.
  ///
  /// nil when the observer could not be made, which the wait reads as no
  /// signal being on its way.
  static func watch(_ window: WindowController.Window) -> Watcher? {
    let watcher = Watcher(window: window)
    guard watcher.start() else { return nil }
    return watcher
  }

  /// Returns once the window reports itself at `expected`, or — for a window
  /// that will not go there — once no move or resize has been reported for
  /// `quiet`, or after `timeout`.
  ///
  /// `expected` is what makes this quick. A quiet period can only conclude
  /// that nothing has happened for a while; a window seen at the frame it was
  /// asked for has said it is finished, and waiting past that is time the next
  /// press spends held for nothing. Windows that refuse the size never match,
  /// and those are the ones the quiet period is still there for.
  static func waitUntilQuiet(
    _ watcher: Watcher?,
    window: WindowController.Window,
    expecting expected: CGRect,
    quiet: Duration,
    timeout: Duration
  ) async {
    guard let watcher else {
      // No observer, so no signal. Wait out the quiet period and read whatever
      // is there.
      try? await Task.sleep(for: quiet)
      return
    }
    defer { watcher.stop() }

    var checked: ContinuousClock.Instant?
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
      // Short, because this loop is what the next press waits behind, and a
      // window is usually done within a few milliseconds of the write.
      try? await Task.sleep(for: .milliseconds(10))
      if Task.isCancelled { return }
      guard let last = watcher.lastEventAt else { continue }
      // Read only on a report. A window that says nothing is one there is
      // nothing to read, and the wait would be paying for the read every tick.
      if last != checked {
        checked = last
        if WindowController.frame(of: window) == expected { return }
      }
      if last.duration(to: .now) >= quiet { return }
    }
  }

  /// Holds the observer from before the write until the wait is over.
  @MainActor
  final class Watcher {
    private(set) var lastEventAt: ContinuousClock.Instant?

    private let window: WindowController.Window
    private var observer: AXObserver?

    init(window: WindowController.Window) {
      self.window = window
    }

    func start() -> Bool {
      var observer: AXObserver?
      guard
        AXObserverCreate(window.processID, settleCallback, &observer) == .success,
        let observer
      else { return false }

      let context = Unmanaged.passUnretained(self).toOpaque()
      for name in [kAXWindowResizedNotification, kAXWindowMovedNotification] {
        AXObserverAddNotification(observer, window.element, name as CFString, context)
      }
      // .commonModes so the window is still watched while a menu is open.
      CFRunLoopAddSource(
        CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .commonModes)
      self.observer = observer
      return true
    }

    func stop() {
      guard let observer else { return }
      CFRunLoopRemoveSource(
        CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .commonModes)
      self.observer = nil
    }

    fileprivate func recordEvent() {
      lastEventAt = .now
    }
  }
}

/// The Accessibility callback. Runs on the run loop the source was added to,
/// which is the main one.
private func settleCallback(
  _ observer: AXObserver,
  _ element: AXUIElement,
  _ notification: CFString,
  _ context: UnsafeMutableRawPointer?
) {
  guard let context else { return }
  // The unwrap happens before the isolated call so the raw pointer — which
  // Swift cannot prove is safe to hand across — never crosses the boundary.
  let watcher = Unmanaged<WindowSettle.Watcher>.fromOpaque(context).takeUnretainedValue()
  MainActor.assumeIsolated { watcher.recordEvent() }
}

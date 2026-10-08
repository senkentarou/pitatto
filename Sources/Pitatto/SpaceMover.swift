// SpaceMover.swift
// Sends a window to the neighbouring Desktop.

import AppKit
import PitattoCore

/// Does what a person does by hand: holds the window by its title bar and
/// switches Desktops, which makes macOS carry the window along.
///
/// There is no public call that puts another app's window on another Desktop,
/// and the private ones stopped working on other processes' windows in
/// macOS 14.5 unless System Integrity Protection is turned off.
@MainActor
enum SpaceMover {

  /// How long the window is held before the Desktop switch is pressed. macOS
  /// has to have registered the drag first, or the switch leaves the window
  /// behind.
  private static let grabDelay: Duration = .milliseconds(50)

  /// The ceiling on waiting for the switch, for a press at the last Desktop in
  /// the row, where macOS bounces instead of switching.
  private static let switchTimeout: Duration = .seconds(1)

  static func move(_ window: WindowController.Window, toward direction: SpaceDirection) async {
    let hotKeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
      .dictionary(forKey: "AppleSymbolicHotKeys")
    guard let shortcut = SystemSpaceShortcut.resolve(direction, in: hotKeys) else {
      Diagnostics.trace("space \(direction.rawValue): the macOS shortcut is turned off")
      return
    }
    guard let grab = WindowController.grabPoint(of: window) else { return }
    let cursor = CGEvent(source: nil)?.location

    postMouse(.mouseMoved, at: grab)
    postMouse(.leftMouseDown, at: grab)
    try? await Task.sleep(for: grabDelay)
    let switched = await waitForSpaceChange { postKey(shortcut) }
    postMouse(.leftMouseUp, at: grab)
    if let cursor {
      CGWarpMouseCursorPosition(cursor)
    }
    Diagnostics.trace(
      "space \(direction.rawValue) pid=\(window.processID) grab=\(Int(grab.x)),\(Int(grab.y))"
        + " switched=\(switched)")
  }

  /// Runs `trigger` and returns once macOS reports the active Desktop changed,
  /// or false after `switchTimeout`.
  private static func waitForSpaceChange(after trigger: () -> Void) async -> Bool {
    let watch = SpaceChangeWatch()
    let center = NSWorkspace.shared.notificationCenter
    let token = center.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
    ) { _ in
      MainActor.assumeIsolated { watch.changed = true }
    }
    defer { center.removeObserver(token) }

    trigger()
    let deadline = ContinuousClock.now.advanced(by: switchTimeout)
    while !watch.changed, ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(10))
    }
    return watch.changed
  }

  /// The flags are set outright. The person is still holding the modifiers of
  /// the Pitatto shortcut, and a mouse-down that picked up ⌃ from them would be
  /// a right click.
  private static func postMouse(_ type: CGEventType, at point: CGPoint) {
    guard
      let event = CGEvent(
        mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
    else { return }
    event.flags = []
    event.post(tap: .cghidEventTap)
  }

  private static func postKey(_ shortcut: SystemSpaceShortcut) {
    for keyDown in [true, false] {
      guard
        let event = CGEvent(
          keyboardEventSource: nil, virtualKey: CGKeyCode(shortcut.keyCode), keyDown: keyDown)
      else { continue }
      event.flags = CGEventFlags(rawValue: shortcut.flags)
      event.post(tap: .cghidEventTap)
    }
  }
}

@MainActor
private final class SpaceChangeWatch {
  var changed = false
}

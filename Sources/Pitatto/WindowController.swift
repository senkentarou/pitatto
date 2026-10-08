// WindowController.swift
// Reads and writes the frontmost window through the Accessibility API — the
// only public way to move a window belonging to another app.

import AppKit
import ApplicationServices
import PitattoCore

@MainActor
enum WindowController {

  struct Window {
    let element: AXUIElement
    let processID: pid_t
  }

  /// The focused window of the app in front, or nil when the front is the
  /// desktop or an app with no window.
  static func frontmostWindow() -> Window? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    return focusedWindow(ofProcess: app.processIdentifier)
  }

  static func focusedWindow(ofProcess processID: pid_t) -> Window? {
    let application = AXUIElementCreateApplication(processID)
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value)
        == .success,
      let value,
      CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    return Window(element: (value as! AXUIElement), processID: processID)
  }

  /// A window in macOS's own full screen owns its Space, so moving it inside
  /// that Space would do nothing visible and resizing it is refused.
  static func isFullScreen(_ window: Window) -> Bool {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(window.element, "AXFullScreen" as CFString, &value) == .success
    else { return false }
    return (value as? Bool) ?? false
  }

  /// The window's frame in AppKit coordinates.
  static func frame(of window: Window) -> CGRect? {
    guard
      let origin = point(window.element, kAXPositionAttribute),
      let size = size(window.element, kAXSizeAttribute)
    else { return nil }
    return FrameCalculator.appKitFrame(
      axOrigin: origin, size: size, primaryScreenHeight: ScreenService.primaryScreenHeight)
  }

  /// The smallest the window says it will go, or nil when it does not say.
  ///
  /// Two spellings because that is what windows answer to: `AXMinSize` is the
  /// one AppKit publishes, `AXMinimumSize` turns up on windows that do not.
  static func minimumSize(of window: Window) -> CGSize? {
    size(window.element, "AXMinSize") ?? size(window.element, "AXMinimumSize")
  }

  /// Sends the window to `target`, with the writes `FrameCalculator.plan`
  /// decides on.
  ///
  /// Nothing is read back here. Accessibility has no completion, so a size read
  /// straight after the write catches an app that animates its resize partway
  /// through, at a size the window never actually settles on. Correcting the
  /// position from such a number throws the window somewhere it then has to be
  /// pulled back from, which is a worse flicker than the one it was meant to
  /// fix. The correction is `seat`, run once the window has stopped moving.
  ///
  /// - Parameter skipResize: the window is known to be at a size it refused to
  ///   go below, so the size is left alone.
  /// - Returns: whether anything was written. A window asked for nothing is not
  ///   going to move, which is what the caller needs to know before it waits
  ///   for a report of one.
  static func place(
    _ window: Window,
    for action: SnapAction,
    from current: CGRect,
    to target: CGRect,
    in workArea: CGRect,
    skipResize: Bool
  ) -> Bool {
    let application = AXUIElementCreateApplication(window.processID)
    // An app runs its windows in "enhanced user interface" mode once an
    // assistive client has talked to it. In that mode AppKit animates a frame
    // change and answers a position or size read with where the window is
    // going rather than where it is — a window that visibly slides into place
    // under a repeated press, and a repeat judgement that never matches. Off
    // for the write, back on afterwards so VoiceOver still works.
    let hadEnhancedUserInterface = isEnhancedUserInterfaceEnabled(application)
    if hadEnhancedUserInterface {
      setBool(application, "AXEnhancedUserInterface", false)
    }
    defer {
      if hadEnhancedUserInterface {
        setBool(application, "AXEnhancedUserInterface", true)
      }
    }

    let steps = FrameCalculator.plan(
      from: current, to: target, for: action, in: workArea, skipResize: skipResize)
    let screenHeight = ScreenService.primaryScreenHeight
    for step in steps {
      switch step {
      case .move(let destination):
        setPoint(
          window.element,
          FrameCalculator.axOrigin(of: destination, primaryScreenHeight: screenHeight))
      case .resize(let size):
        setSize(window.element, size)
      }
    }

    Diagnostics.trace(
      "  place enhancedUI=\(hadEnhancedUserInterface) steps=\(steps.map(describe))")
    return !steps.isEmpty
  }

  private static func describe(_ step: FrameCalculator.WriteStep) -> String {
    switch step {
    case .move(let destination): return "move→[\(Diagnostics.describe(destination))]"
    case .resize(let size): return "resize→\(Int(size.width))×\(Int(size.height))"
    }
  }

  /// Reads where the window came to rest and, if it refused the size it was
  /// given, pushes it back against the edge `action` named.
  ///
  /// Run after the window has stopped moving, which is the only time the size
  /// read means anything. Returns where the window is now.
  static func seat(
    _ window: Window,
    for action: SnapAction,
    at targetOrigin: CGPoint,
    in workArea: CGRect
  ) -> CGRect? {
    guard let settled = frame(of: window) else { return nil }
    let seated = FrameCalculator.reseat(
      CGRect(origin: targetOrigin, size: settled.size), for: action, in: workArea)
    guard seated.origin != settled.origin else {
      Diagnostics.trace("  seat none settled=[\(Diagnostics.describe(settled))]")
      return settled
    }
    setPoint(
      window.element,
      FrameCalculator.axOrigin(of: seated, primaryScreenHeight: ScreenService.primaryScreenHeight))
    Diagnostics.trace("  seat moved to [\(Diagnostics.describe(seated))]")
    return seated
  }

  /// Where a press grabs the window to drag it, in the top-left-origin
  /// coordinates that both Accessibility and `CGEvent` use.
  ///
  /// Just past the zoom button, level with it: in the title bar of a plain
  /// window, and in the gap before the first tab of a window that draws its
  /// tabs there — grabbing a tab would tear it off instead of moving the
  /// window. A window with no zoom button is grabbed at the middle of its top.
  static func grabPoint(of window: Window) -> CGPoint? {
    if let button = element(window.element, kAXZoomButtonAttribute),
      let origin = point(button, kAXPositionAttribute),
      let size = size(button, kAXSizeAttribute)
    {
      return CGPoint(x: origin.x + size.width + 6, y: origin.y + size.height / 2)
    }
    guard
      let origin = point(window.element, kAXPositionAttribute),
      let size = size(window.element, kAXSizeAttribute)
    else { return nil }
    return CGPoint(x: origin.x + size.width / 2, y: origin.y + 6)
  }

  // MARK: - Attribute plumbing

  private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
      let value,
      CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    return (value as! AXUIElement)
  }

  private static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
    guard let value = axValue(element, attribute) else { return nil }
    var point = CGPoint.zero
    guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
    return point
  }

  private static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
    guard let value = axValue(element, attribute) else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(value, .cgSize, &size) else { return nil }
    return size
  }

  private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
      let value,
      CFGetTypeID(value) == AXValueGetTypeID()
    else { return nil }
    return (value as! AXValue)
  }

  /// Write failures are dropped on the floor on purpose: a window that refuses
  /// a size — an alert, a window with a fixed aspect — still takes the position
  /// write, and moving it alone is better than nothing happening.
  private static func setPoint(_ element: AXUIElement, _ point: CGPoint) {
    var point = point
    guard let value = AXValueCreate(.cgPoint, &point) else { return }
    AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
  }

  private static func setSize(_ element: AXUIElement, _ size: CGSize) {
    var size = size
    guard let value = AXValueCreate(.cgSize, &size) else { return }
    AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
  }

  private static func isEnhancedUserInterfaceEnabled(_ application: AXUIElement) -> Bool {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(application, "AXEnhancedUserInterface" as CFString, &value)
        == .success
    else { return false }
    return (value as? Bool) ?? false
  }

  private static func setBool(_ element: AXUIElement, _ attribute: String, _ flag: Bool) {
    AXUIElementSetAttributeValue(element, attribute as CFString, flag as CFBoolean)
  }
}

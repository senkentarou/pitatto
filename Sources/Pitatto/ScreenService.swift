// ScreenService.swift
// Which display a window is on, and how much of it a window may use.

import AppKit
import PitattoCore

@MainActor
enum ScreenService {
  /// The height of the screen holding the menu bar — the screen AppKit and the
  /// Accessibility API both put their origin on, and so the only number the
  /// coordinate flip needs.
  static var primaryScreenHeight: CGFloat {
    NSScreen.screens.first?.frame.height ?? 0
  }

  /// The work area of the display `frame` sits on: `visibleFrame`, which is the
  /// screen minus the menu bar and the Dock.
  ///
  /// The display is the one the window overlaps most. A window dragged
  /// half off every screen overlaps none of them, and falls back to the screen
  /// under the pointer.
  static func workArea(for frame: CGRect) -> CGRect? {
    let screens = NSScreen.screens
    guard !screens.isEmpty else { return nil }

    if let index = FrameCalculator.indexOfScreen(mostOverlapping: frame, in: screens.map(\.frame)) {
      return screens[index].visibleFrame
    }

    let pointer = NSEvent.mouseLocation
    let underPointer = screens.first { $0.frame.contains(pointer) }
    return (underPointer ?? screens[0]).visibleFrame
  }
}

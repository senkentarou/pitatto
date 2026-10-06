// Diagnostics.swift
// Opt-in tracing for the one path that cannot be covered by tests.

import Foundation
import os

/// Traces one press, from the frame the window was at to the frame it ended up
/// with.
///
/// This exists because the snapping path needs a granted Accessibility
/// permission and a real window, so `swift test` can never reach it — when the
/// repeat judgement misbehaves on a machine, the alternative to a trace is
/// guessing. Off unless asked for:
///
///     defaults write com.senkentarou.pitatto.app debugLog -bool true
///     log stream --predicate 'subsystem == "com.senkentarou.pitatto.app"'
///
/// What is traced keeps the app's promise: geometry and the owning process id,
/// never a window title or anything else read from another app.
enum Diagnostics {
  static let isEnabled = UserDefaults.standard.bool(forKey: "debugLog")

  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "pitatto", category: "trace")

  /// `notice`, not `info`: info-level messages live in a memory buffer that
  /// `log show` cannot read afterwards, and a trace of a key press is something
  /// you go looking for once the press has already misbehaved.
  static func trace(_ message: @autoclosure () -> String) {
    guard isEnabled else { return }
    let text = message()
    logger.notice("\(text, privacy: .public)")
  }

  static func describe(_ rect: CGRect) -> String {
    "\(Int(rect.origin.x.rounded())) \(Int(rect.origin.y.rounded()))"
      + " \(Int(rect.width.rounded())) \(Int(rect.height.rounded()))"
  }
}

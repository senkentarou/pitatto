// PermissionService.swift
// Knows whether Accessibility is granted, and points at where to grant it.

import AppKit
import ApplicationServices

/// Watches the one permission this app needs.
///
/// Polling rather than waiting for a notification because macOS does not send
/// one: a grant made in System Settings reaches a running process only when it
/// next asks. It is also what makes both directions work — the menu losing its
/// two warning lines when the switch goes on, and getting them back when it
/// goes off.
@MainActor
final class PermissionService {
  private(set) var isTrusted = false
  var onChange: ((Bool) -> Void)?

  /// One second: the menu's two warning lines should be gone within a few
  /// seconds of granting, and a five second period would spend that on the
  /// poll alone.
  private static let pollInterval: TimeInterval = 1

  /// Held, not read. `RunLoop.add` retains the timer too, but the poll is the
  /// only thing that notices the grant changing, so its lifetime is not left to
  /// the run loop alone.
  private var timer: Timer?

  func start() {
    isTrusted = AXIsProcessTrusted()
    let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.poll() }
    }
    // .common so the poll keeps running while the menu is open — which is
    // exactly when someone is watching for the two lines to disappear.
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  /// Shows the system prompt and opens the Accessibility pane.
  ///
  /// Both, because they do different jobs: the prompt is what puts Pitatto into
  /// the list at all (macOS shows it at most once per app), and the pane is
  /// where the switch is.
  func requestAndOpenSettings() {
    // The literal, not `kAXTrustedCheckOptionPrompt`: that symbol is imported
    // as a global `var`, which Swift 6 will not let a concurrent context read.
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    {
      NSWorkspace.shared.open(url)
    }
  }

  private func poll() {
    let trusted = AXIsProcessTrusted()
    guard trusted != isTrusted else { return }
    isTrusted = trusted
    onChange?(trusted)
  }
}

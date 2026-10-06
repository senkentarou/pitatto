// FrameDump.swift
// `Pitatto --print-frame [app]`: the frontmost window's geometry, on one line.

import AppKit
import ApplicationServices
import PitattoCore

/// A self-check for where a snap put the window.
///
/// Shipped in every build, not just a debug one: the frames it has to confirm
/// are the ones the released `.app` produces, and a flag compiled out of the
/// release build would be checking a different binary.
///
/// The optional app argument exists because the answer is otherwise always the
/// terminal: a run from a shell makes that terminal the frontmost app, so
/// `--print-frame` with no argument reports the terminal's own window. Naming
/// the app — by bundle identifier or by the name in the Dock — asks that app
/// for its focused window instead.
@MainActor
enum FrameDump {
  static func run(argument: String?) -> Never {
    guard AXIsProcessTrusted() else {
      FileHandle.standardError.write(
        Data("アクセシビリティが許可されていません\n".utf8))
      exit(1)
    }

    guard let window = window(for: argument) else {
      FileHandle.standardError.write(Data("前面にウィンドウがありません\n".utf8))
      exit(1)
    }

    guard let frame = WindowController.frame(of: window) else {
      FileHandle.standardError.write(Data("ウィンドウの位置とサイズが読めません\n".utf8))
      exit(1)
    }

    // AppKit coordinates and whole points, so the numbers line up with what
    // FrameCalculator was asked for.
    print(Diagnostics.describe(frame))
    exit(0)
  }

  private static func window(for argument: String?) -> WindowController.Window? {
    guard let argument else { return WindowController.frontmostWindow() }
    guard let application = runningApplication(matching: argument) else { return nil }
    return WindowController.focusedWindow(ofProcess: application.processIdentifier)
  }

  private static func runningApplication(matching argument: String) -> NSRunningApplication? {
    let running = NSWorkspace.shared.runningApplications
    return running.first { $0.bundleIdentifier == argument }
      ?? running.first { $0.localizedName == argument }
  }
}

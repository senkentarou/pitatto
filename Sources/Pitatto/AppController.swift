// AppController.swift
// Where the hot keys, the window and the settings meet. Holds no judgement of
// its own: the arithmetic lives in PitattoCore, the OS calls in the services.

import AppKit
import Combine
import PitattoCore

@MainActor
final class AppController: ObservableObject {

  @Published private(set) var isTrusted = false

  /// Whether the app starts at login. Read back from macOS rather than stored:
  /// the switch lives in System Settings as much as here, and a remembered copy
  /// would be the one that lies.
  @Published private(set) var launchAtLogin = false

  /// The shortcuts macOS refused to register, and the ones bound to a
  /// combination another Pitatto command already owns. Both make the row go
  /// red; the wording is the settings screen's business.
  @Published private(set) var unavailableShortcuts: Set<SnapCommand> = []

  /// Which field is waiting for a key press, if any. The hot keys are handed
  /// back for the duration, so the recorder can see ⌥⌃→ instead of having it
  /// swallowed by the registration it is about to replace.
  ///
  /// Held here rather than in each field, because only one field can be
  /// recording and no field can see the others. A field that kept its own flag
  /// stayed lit — and kept its key monitor installed — when the person gave up
  /// on it and pressed a different one.
  @Published private(set) var recordingCommand: SnapCommand?

  /// What the last recording could not take. The binding is left as it was, so
  /// this is the only trace of the attempt; it is cleared by the next one.
  @Published private(set) var rejection: Rejection?

  struct Rejection: Equatable {
    let command: SnapCommand
    let combo: KeyCombo
    /// The row that already owns the combination, when that is the reason.
    let heldBy: SnapCommand?
  }

  var isRecording: Bool { recordingCommand != nil }

  @Published var settings: Settings {
    didSet {
      guard settings != oldValue else { return }
      store.save(settings)
      if settings.shortcuts != oldValue.shortcuts, !isRecording {
        applyShortcuts()
      }
    }
  }

  /// Set by the menu bar label once SwiftUI can open windows.
  var openWindow: ((String) -> Void)?

  let updater = UpdateController()

  private let store: SettingsStore
  private let permission = PermissionService()
  private let hotKeys = HotKeyCenter.shared

  /// How long the window has to go without a reported move or resize before it
  /// counts as settled. Chrome changes the window more than once per write, and
  /// this has to span the gap between those.
  private static let settleQuiet: Duration = .milliseconds(250)

  /// The ceiling on that wait, for a window that ignored the write and will
  /// never report anything.
  private static let settleTimeout: Duration = .milliseconds(1500)

  /// The repeat-press judgement and what each press left behind. The session
  /// decides; this class reads the window and performs what it decided.
  private var session = SnapSession()

  /// The window the session's held press is for. Kept here because an
  /// Accessibility element cannot cross into PitattoCore.
  private var pendingWindow: WindowController.Window?

  private var hasStarted = false

  init(store: SettingsStore = SettingsStore()) {
    self.store = store
    self.settings = store.load()
  }

  // MARK: - Lifecycle

  func start() {
    // The menu bar label's onAppear is the only caller, but SwiftUI makes no
    // promise about how often a view appears; starting twice would leave two
    // timers running and two handlers on every hot key.
    guard !hasStarted else { return }
    hasStarted = true

    hotKeys.onPress = { [weak self] command in self?.snap(command) }
    applyShortcuts()

    permission.onChange = { [weak self] trusted in self?.isTrusted = trusted }
    permission.start()
    isTrusted = permission.isTrusted

    launchAtLogin = LoginItem.isEnabled

    updater.start()
  }

  // MARK: - Snapping

  /// One press of one shortcut.
  ///
  /// Every early return is silent: no window in front, a window in macOS's own
  /// full screen, or a window that will not say where it is all leave the
  /// screen untouched and make no sound.
  func snap(_ command: SnapCommand) {
    guard isTrusted else { return }
    guard let window = WindowController.frontmostWindow() else { return }
    guard !WindowController.isFullScreen(window) else { return }
    guard let current = WindowController.frame(of: window) else { return }
    guard let workArea = ScreenService.workArea(for: current) else { return }

    // The window is asked what it will not go below, and the frame is worked
    // out from that rather than written and corrected. A window narrower than
    // its own minimum ends up hanging off the edge it was sent to, and a size
    // read back straight after the write comes from an app that may not have
    // applied the resize yet.
    let minimumSize = WindowController.minimumSize(of: window)
    let effect = session.press(
      SnapSession.Press(
        action: command.action, size: command.size, processID: window.processID,
        current: current, workArea: workArea, minimumSize: minimumSize, now: .now))
    let plan = effect.plan
    Diagnostics.trace(
      "\(plan.action.rawValue) \(plan.size) pid=\(plan.processID)"
        + " current=[\(Diagnostics.describe(current))] target=[\(Diagnostics.describe(plan.target))]"
        + " min=\(minimumSize.map { "\(Int($0.width))×\(Int($0.height))" } ?? "unknown")")
    perform(effect, on: window, from: current)
  }

  /// Carries out what the session decided for a press.
  private func perform(
    _ effect: SnapSession.Effect, on window: WindowController.Window, from current: CGRect
  ) {
    switch effect {
    case .hold:
      pendingWindow = window
      Diagnostics.trace("  held — the window is still moving")
    case .leave:
      break
    case .write(let plan, let skipResize):
      // Listening starts before the write, not after it: the window moves inside
      // the write call and posts its move and resize there, so an observer set up
      // afterwards hears nothing at all.
      let watcher = WindowSettle.watch(window)
      let wrote = WindowController.place(
        window, for: plan.action, from: current, to: plan.target, in: plan.workArea,
        skipResize: skipResize)
      session.didWrite(plan, wrote: wrote, current: current)

      // Nothing was asked of the window, so nothing is going to move and no move
      // or resize will ever be reported. Waiting for one runs the whole timeout
      // and holds every press behind it for that long — which is what a sequence
      // step narrower than the window's own minimum width does, on every press.
      guard wrote else {
        watcher?.stop()
        return
      }
      settle(plan, on: window, watching: watcher)
    }
  }

  /// Reads where the window came to rest, pushes it back against its edge if it
  /// refused the size, and then lets the press that was held behind it through.
  ///
  /// A second pass rather than part of the write, because Accessibility reports
  /// no completion: an app that animates its resize answers a size read taken
  /// straight afterwards with a number the window never settles on. Seating
  /// from that number throws the window across the screen and back.
  private func settle(
    _ plan: SnapSession.Plan, on window: WindowController.Window,
    watching watcher: WindowSettle.Watcher?
  ) {
    Task { [weak self] in
      guard let self else { return }
      await WindowSettle.waitUntilQuiet(
        watcher, window: window, expecting: plan.target,
        quiet: Self.settleQuiet, timeout: Self.settleTimeout)

      let measured = WindowController.seat(
        window, for: plan.action, at: plan.target.origin, in: plan.workArea)
      if let measured {
        Diagnostics.trace("  → measured=[\(Diagnostics.describe(measured))]")
      }

      guard case .apply(let next) = self.session.settled(plan, measured: measured) else { return }
      let nextWindow = self.pendingWindow
      self.pendingWindow = nil
      guard let nextWindow, let current = WindowController.frame(of: nextWindow) else { return }
      Diagnostics.trace(
        "  releasing held \(next.action.rawValue) \(next.size)"
          + " current=[\(Diagnostics.describe(current))]")
      self.perform(self.session.release(next, current: current), on: nextWindow, from: current)
    }
  }

  // MARK: - Settings

  func setLaunchAtLogin(_ enabled: Bool) {
    launchAtLogin = LoginItem.setEnabled(enabled) == .enabled
  }

  // MARK: - Recording a shortcut

  /// Starts recording `command`, ending whatever was recording before it.
  func beginRecording(for command: SnapCommand) {
    guard recordingCommand != command else { return }
    recordingCommand = command
    rejection = nil
    hotKeys.unregisterAll()
  }

  /// Takes a combination away from `command`. The × on a field, which is the
  /// discoverable half of ⌫ — that one only works while the field is armed,
  /// which is not where someone looking at a filled field starts.
  func clearShortcut(for command: SnapCommand) {
    rejection = nil
    settings.shortcuts[command] = nil
  }

  func endRecording(with outcome: ShortcutRecorder.Outcome, for command: SnapCommand) {
    guard recordingCommand == command else { return }
    recordingCommand = nil
    switch outcome {
    case .assigned(let combo):
      assign(combo, to: command)
    case .cleared:
      settings.shortcuts[command] = nil
      // Not left to `didSet`: a field that was already empty has not changed,
      // and the keys handed back when recording started would stay handed back.
      applyShortcuts()
    case .cancelled:
      // Nothing changed — but the keys were handed back when recording
      // started and have to be taken again.
      applyShortcuts()
    }
  }

  /// Binds `combo` only if it can actually be registered.
  ///
  /// A combination another app holds, or one another row already owns, is put
  /// back rather than saved. Saving it and colouring the row red left the
  /// person with two losses instead of one: the combination they just pressed
  /// does nothing, and the key that used to work is gone.
  private func assign(_ combo: KeyCombo, to command: SnapCommand) {
    let previous = settings.shortcuts[command]
    let heldBy = settings.shortcuts.command(holding: combo, otherThan: command)
    settings.shortcuts[command] = combo
    applyShortcuts()
    guard heldBy != nil || unavailableShortcuts.contains(command) else { return }
    settings.shortcuts[command] = previous
    applyShortcuts()
    rejection = Rejection(command: command, combo: combo, heldBy: heldBy)
  }

  // MARK: - Windows

  func openSettingsWindow() {
    openWindow?(WindowID.settings)
    // A menu bar app is .accessory, so its windows open behind whatever is in
    // front. Raising the app is what puts the settings window on screen — and
    // it is also what lets the recorder receive key presses.
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }

  func openUpdateWindow() {
    openWindow?(WindowID.update)
    NSApp.activate(ignoringOtherApps: true)
  }

  func settingsWindowDidClose() {
    NSApp.setActivationPolicy(.accessory)
  }

  func openAccessibilitySettings() {
    permission.requestAndOpenSettings()
  }

  func quit() {
    NSApp.terminate(nil)
  }

  // MARK: - Private

  private func applyShortcuts() {
    // `duplicatedCommands` still runs even though a clash is now refused as it
    // is typed: a blob edited by hand can hold one, and a row that does
    // nothing should say so rather than look bound.
    unavailableShortcuts = hotKeys.register(settings.shortcuts)
      .union(settings.shortcuts.duplicatedCommands())
  }
}

enum WindowID {
  static let settings = "settings"
  static let update = "update"
}

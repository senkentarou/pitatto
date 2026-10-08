// ShortcutRecorder.swift
// The key-recording field: press it, then press the combination.

import AppKit
import PitattoCore
import SwiftUI

struct ShortcutRecorder: View {
  /// What a recording ended as. Three outcomes, not two: ⎋ leaves the binding
  /// alone and ⌫ takes it away, and a field that ships empty needs both.
  enum Outcome {
    case cancelled
    case cleared
    case assigned(KeyCombo)
  }

  let command: ShortcutCommand
  /// nil when nothing is bound.
  let combo: KeyCombo?
  /// The row goes red when macOS refused the registration, or when another
  /// Pitatto command already owns the combination.
  let isUnavailable: Bool
  /// The sentence the row shows under a red field. Spoken with the field, since
  /// the row's caption is a separate element nothing ties to it.
  let hint: String?
  /// Owned by the controller, not by this field: a field cannot see the others,
  /// so it cannot know it has been abandoned for one of them.
  let isRecording: Bool
  let onBeginRecording: () -> Void
  let onClear: () -> Void
  let onFinish: (Outcome) -> Void

  @State private var monitor: Any?

  /// With the field's own padding this is `SettingsChrome.gridColumnWidth`, so
  /// a grid field is exactly as wide as its column.
  private static let minimumWidth: CGFloat = 76

  var body: some View {
    Button {
      onBeginRecording()
    } label: {
      cap
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(label(for: command)) のショートカット")
    .accessibilityValue(isRecording ? "キーを押す…" : (combo.map(KeyLabel.text(for:)) ?? "未設定"))
    .accessibilityHint(hint ?? "")
    // The monitor follows the controller's flag, so it is torn down both when
    // this field finishes and when another field takes over from it.
    .onChange(of: isRecording) { _, isArmed in
      if isArmed { startMonitor() } else { stopMonitor() }
    }
    // Closing the window or leaving the tab mid-recording cancels it. Only
    // stopping the monitor would leave the hot keys handed back when recording
    // started, and nothing would take them again.
    .onDisappear {
      if isRecording { finish(.cancelled) }
    }
  }

  private var cap: some View {
    // "キーを押す…" in full, in every field. Shortened to "押す…" it reads as
    // an instruction to click the thing that has just been clicked.
    Text(isRecording ? "キーを押す…" : (combo.map(KeyLabel.text(for:)) ?? "—"))
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(capColour)
      // Symmetric, so the cap stays centred in the field rather than sliding
      // left when the × appears — and clear of the × either way.
      .padding(.horizontal, showsClearButton ? 14 : 0)
      .frame(minWidth: Self.minimumWidth)
      // An overlay, not a `Spacer` beside it: a spacer is infinitely flexible,
      // so the field grew to whatever width the row would give it.
      .overlay(alignment: .trailing) {
        if showsClearButton { clearButton }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(SettingsChrome.background)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .strokeBorder(borderColour, lineWidth: isRecording ? 2 : 1)
      )
      .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
  }

  private var showsClearButton: Bool { combo != nil && !isRecording }

  private var clearButton: some View {
    Button(action: onClear) {
      Image(systemName: "xmark.circle.fill")
        .font(.system(size: 12))
        // The foreground colour, so the disc reads as a solid mark on the
        // field in both appearances rather than a white blob in the light one.
        .foregroundStyle(SettingsChrome.primaryText.opacity(0.7))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(label(for: command)) の割り当てを消す")
  }

  private var capColour: Color {
    if isUnavailable { return .red }
    return combo == nil ? SettingsChrome.tertiaryText : SettingsChrome.primaryText
  }

  private var borderColour: Color {
    if isRecording { return .accentColor }
    return isUnavailable ? .red : SettingsChrome.border
  }

  /// A local monitor rather than a first-responder view: the window is already
  /// key while the settings screen is open, and this keeps the field itself a
  /// plain SwiftUI button.
  private func startMonitor() {
    guard monitor == nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
      handle(event)
    }
  }

  private func handle(_ event: NSEvent) -> NSEvent? {
    // Every event is swallowed while armed, including the modifiers on their
    // own: a ⌥ held on the way to ⌥⌃→ must not reach the window underneath.
    guard event.type == .keyDown else { return nil }

    if event.keyCode == KeyCode.escape {
      finish(.cancelled)
      return nil
    }

    // ⌫ on its own unbinds. Without it a key once assigned could only ever be
    // replaced, and the fifteen sized commands all start out with nothing.
    if event.keyCode == KeyCode.delete {
      finish(.cleared)
      return nil
    }

    let combo = KeyCombo(keyCode: event.keyCode, modifiers: modifiers(from: event.modifierFlags))
    guard combo.hasGlobalModifier else { return nil }

    finish(.assigned(combo))
    return nil
  }

  private func finish(_ outcome: Outcome) {
    stopMonitor()
    onFinish(outcome)
  }

  private func stopMonitor() {
    guard let monitor else { return }
    NSEvent.removeMonitor(monitor)
    self.monitor = nil
  }

  private func modifiers(from flags: NSEvent.ModifierFlags) -> KeyCombo.Modifiers {
    var modifiers: KeyCombo.Modifiers = []
    if flags.contains(.control) { modifiers.insert(.control) }
    if flags.contains(.option) { modifiers.insert(.option) }
    if flags.contains(.shift) { modifiers.insert(.shift) }
    if flags.contains(.command) { modifiers.insert(.command) }
    return modifiers
  }
}

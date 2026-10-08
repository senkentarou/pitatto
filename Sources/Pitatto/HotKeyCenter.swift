// HotKeyCenter.swift
// The global shortcuts, registered with Carbon.

import Carbon.HIToolbox
import PitattoCore

/// Four-char code `PITA`, stamped on every hot key this app owns so the handler
/// can ignore one registered by a framework linked into the same process.
private let hotKeySignature: OSType = "PITA".utf8.reduce(0) { $0 << 8 | OSType($1) }

/// Registers the shortcuts and calls back when one is pressed.
///
/// `RegisterEventHotKey` rather than an event tap: it needs no permission of
/// its own, and it consumes the key before the frontmost app sees it, so ⌥⌃→ in
/// Safari's address bar does nothing to Safari.
@MainActor
final class HotKeyCenter {
  static let shared = HotKeyCenter()

  /// Called on the main thread when one of the registered keys is pressed.
  var onPress: ((ShortcutCommand) -> Void)?

  private var refs: [ShortcutCommand: EventHotKeyRef] = [:]
  private var eventHandler: EventHandlerRef?

  private init() {}

  /// Replaces the registrations with `shortcuts`, and returns the actions
  /// macOS refused.
  ///
  /// Failures are returned rather than thrown because the rest have to keep
  /// working: the one bad row goes red in the settings, and the app does not
  /// stop taking keys.
  func register(_ shortcuts: Shortcuts) -> Set<ShortcutCommand> {
    unregisterAll()
    installEventHandlerIfNeeded()

    var failed: Set<ShortcutCommand> = []
    for command in ShortcutCommand.allCases {
      // Most of the sized commands have no key. There is nothing to register
      // for those, and nothing that could fail.
      guard let combo = shortcuts[command] else { continue }
      // A blob edited by hand can hold what the recorder refuses to record.
      // Registered, it would hijack a plain key in every app; reported, the row
      // goes red like any other key macOS would not take.
      guard combo.hasGlobalModifier else {
        failed.insert(command)
        continue
      }
      var ref: EventHotKeyRef?
      let id = EventHotKeyID(signature: hotKeySignature, id: identifier(for: command))
      let status = RegisterEventHotKey(
        UInt32(combo.keyCode),
        carbonModifiers(combo.modifiers),
        id,
        GetApplicationEventTarget(),
        0,
        &ref)
      if status == noErr, let ref {
        refs[command] = ref
      } else {
        failed.insert(command)
      }
    }
    return failed
  }

  /// Hands the keys back to whoever else wants them. Used while the settings
  /// window is recording a new shortcut: the recorder has to see ⌥⌃→ as a key
  /// press, and a registered hot key would swallow it first.
  func unregisterAll() {
    for ref in refs.values {
      UnregisterEventHotKey(ref)
    }
    refs.removeAll()
  }

  fileprivate func fire(_ identifier: UInt32) {
    let index = Int(identifier) - 1
    guard ShortcutCommand.allCases.indices.contains(index) else { return }
    onPress?(ShortcutCommand.allCases[index])
  }

  /// The position in `allCases`, one-based — Carbon treats 0 as unset.
  ///
  /// Derived rather than written out: twenty-two hand-assigned numbers would be
  /// twenty-two chances to repeat one, and the value only has to stay put for
  /// as long as the process lives.
  private func identifier(for command: ShortcutCommand) -> UInt32 {
    UInt32((ShortcutCommand.allCases.firstIndex(of: command) ?? 0) + 1)
  }

  private func carbonModifiers(_ modifiers: KeyCombo.Modifiers) -> UInt32 {
    var carbon: UInt32 = 0
    if modifiers.contains(.control) { carbon |= UInt32(controlKey) }
    if modifiers.contains(.option) { carbon |= UInt32(optionKey) }
    if modifiers.contains(.shift) { carbon |= UInt32(shiftKey) }
    if modifiers.contains(.command) { carbon |= UInt32(cmdKey) }
    return carbon
  }

  /// One handler for the process, installed on first use and never removed —
  /// Carbon delivers every hot key press to the application event target, and
  /// re-installing it on each `register` would stack duplicates that each fire
  /// the same action.
  private func installEventHandlerIfNeeded() {
    guard eventHandler == nil else { return }
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed))
    var ref: EventHandlerRef?
    InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, nil, &ref)
    eventHandler = ref
  }
}

/// Carbon's callback. Runs on the main thread: the application event target is
/// serviced by the main run loop, which is what makes `assumeIsolated` sound
/// here.
private func hotKeyEventHandler(
  _ callRef: EventHandlerCallRef?,
  _ event: EventRef?,
  _ context: UnsafeMutableRawPointer?
) -> OSStatus {
  var id = EventHotKeyID()
  let status = GetEventParameter(
    event,
    EventParamName(kEventParamDirectObject),
    EventParamType(typeEventHotKeyID),
    nil,
    MemoryLayout<EventHotKeyID>.size,
    nil,
    &id)
  guard status == noErr, id.signature == hotKeySignature else {
    return OSStatus(eventNotHandledErr)
  }
  MainActor.assumeIsolated {
    HotKeyCenter.shared.fire(id.id)
  }
  return noErr
}

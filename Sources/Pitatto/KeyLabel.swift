// KeyLabel.swift
// What a shortcut looks like on screen.

import Carbon.HIToolbox
import PitattoCore

/// Turns a `KeyCombo` into the caps the settings screen shows.
///
/// The named keys — arrows, ↩, ⎋ — come from `PitattoCore`, which can spell them
/// without asking the OS anything. Everything else is a printable key, and
/// which character it prints depends on the keyboard layout, so that half of
/// the answer has to come from here.
enum KeyLabel {
  static func text(for combo: KeyCombo) -> String {
    combo.modifierSymbols + (combo.namedKeyLabel ?? character(for: combo.keyCode) ?? "…")
  }

  private static func character(for keyCode: UInt16) -> String? {
    guard
      let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
      let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return nil }

    let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
    var deadKeyState: UInt32 = 0
    var length = 0
    var characters = [UniChar](repeating: 0, count: 4)

    let status = data.withUnsafeBytes { buffer -> OSStatus in
      guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
        return OSStatus(paramErr)
      }
      // kUCKeyActionDisplay with no modifiers: the character printed on the key
      // cap, not the one the combination would type. ⌥K prints "K", not "˚".
      return UCKeyTranslate(
        layout,
        keyCode,
        UInt16(kUCKeyActionDisplay),
        0,
        UInt32(LMGetKbdType()),
        OptionBits(kUCKeyTranslateNoDeadKeysBit),
        &deadKeyState,
        characters.count,
        &length,
        &characters)
    }

    guard status == noErr, length > 0 else { return nil }
    return String(utf16CodeUnits: characters, count: length).uppercased()
  }
}

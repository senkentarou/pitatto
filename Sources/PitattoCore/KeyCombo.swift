// KeyCombo.swift
// A hot key, as a virtual key code and the modifiers held with it.

import Foundation

/// One shortcut.
///
/// The key code is the hardware position Carbon and AppKit both use, not a
/// character: the same physical key produces different characters under
/// different layouts, and a hot key follows the position.
public struct KeyCombo: Hashable, Codable, Sendable {
  public var keyCode: UInt16
  public var modifiers: Modifiers

  public init(keyCode: UInt16, modifiers: Modifiers) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
  }

  /// The modifier caps, in the order the README and the settings write them:
  /// ⌥⌃ rather than macOS's own ⌃⌥. Raycast's window management spells the
  /// same shortcuts this way. None of Pitatto's shortcuts appear in a macOS
  /// menu, so nothing on screen disagrees with it.
  public var modifierSymbols: String {
    var symbols = ""
    if modifiers.contains(.option) { symbols += "⌥" }
    if modifiers.contains(.control) { symbols += "⌃" }
    if modifiers.contains(.shift) { symbols += "⇧" }
    if modifiers.contains(.command) { symbols += "⌘" }
    return symbols
  }

  /// The cap for a key macOS names rather than prints. Nil for a key whose cap
  /// depends on the keyboard layout — the caller resolves those, because the
  /// layout is an OS lookup and this target makes no OS calls.
  public var namedKeyLabel: String? { KeyCode.label(for: keyCode) }

  /// Whether the combination may be a global hot key: at least one of ⌃⌥⌘.
  /// A bare key, or ⇧ and a key, would take over typing in every app on the
  /// Mac, and there is no way back from that except quitting Pitatto.
  public var hasGlobalModifier: Bool {
    !modifiers.isDisjoint(with: [.control, .option, .command])
  }
}

/// The virtual key codes this app needs by name.
///
/// Spelled out rather than imported from `Carbon.HIToolbox`: the codes are a
/// stable hardware mapping, and naming them here keeps the decision layer free
/// of an OS framework.
public enum KeyCode {
  public static let `return`: UInt16 = 0x24
  public static let tab: UInt16 = 0x30
  public static let space: UInt16 = 0x31
  public static let delete: UInt16 = 0x33
  public static let escape: UInt16 = 0x35
  public static let keypadEnter: UInt16 = 0x4C
  public static let leftArrow: UInt16 = 0x7B
  public static let rightArrow: UInt16 = 0x7C
  public static let downArrow: UInt16 = 0x7D
  public static let upArrow: UInt16 = 0x7E

  static func label(for keyCode: UInt16) -> String? {
    switch keyCode {
    case `return`: return "↩"
    case tab: return "⇥"
    case space: return "␣"
    case delete: return "⌫"
    case escape: return "⎋"
    case keypadEnter: return "⌤"
    case leftArrow: return "←"
    case rightArrow: return "→"
    case downArrow: return "↓"
    case upArrow: return "↑"
    default: return nil
    }
  }
}

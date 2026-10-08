// SystemSpaceShortcut.swift
// macOS's own "Move left a space" / "Move right a space" key, read out of the
// symbolic hot key preferences.

import Foundation

/// The key macOS switches Desktops on. Sending a window to the next Desktop
/// presses it on the person's behalf, so it has to be the key macOS is
/// actually listening for, not the one it ships with.
public struct SystemSpaceShortcut: Equatable, Sendable {
  public let keyCode: UInt16
  /// `CGEventFlags` as stored by macOS, device-independent bits included.
  public let flags: UInt64

  public init(keyCode: UInt16, flags: UInt64) {
    self.keyCode = keyCode
    self.flags = flags
  }

  /// The key in `com.apple.symbolichotkeys`'s `AppleSymbolicHotKeys` for
  /// `direction`, or nil when the person turned it off.
  ///
  /// An entry that is missing, or that holds only `enabled`, has never been
  /// changed and still means the shipped key.
  public static func resolve(_ direction: SpaceDirection, in hotKeys: [String: Any]?)
    -> SystemSpaceShortcut?
  {
    let shipped = shipped(direction)
    guard let entry = hotKeys?[identifier(direction)] as? [String: Any] else { return shipped }
    if let enabled = entry["enabled"] as? Bool, !enabled { return nil }
    guard
      let value = entry["value"] as? [String: Any],
      let parameters = value["parameters"] as? [Int],
      parameters.count == 3,
      let keyCode = UInt16(exactly: parameters[1]),
      let flags = UInt64(exactly: parameters[2])
    else { return shipped }
    return SystemSpaceShortcut(keyCode: keyCode, flags: flags)
  }

  private static func identifier(_ direction: SpaceDirection) -> String {
    switch direction {
    case .left: return "79"
    case .right: return "81"
    }
  }

  /// ⌃← / ⌃→. An arrow key always carries the function-key bit, so macOS
  /// stores it alongside control.
  private static func shipped(_ direction: SpaceDirection) -> SystemSpaceShortcut {
    let controlAndFunction: UInt64 = 0x84_0000
    switch direction {
    case .left: return SystemSpaceShortcut(keyCode: KeyCode.leftArrow, flags: controlAndFunction)
    case .right: return SystemSpaceShortcut(keyCode: KeyCode.rightArrow, flags: controlAndFunction)
    }
  }
}

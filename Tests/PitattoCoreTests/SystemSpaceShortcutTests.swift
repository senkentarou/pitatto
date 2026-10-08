// SystemSpaceShortcutTests.swift
// Verifies which key is pressed to switch Desktops, read from the shapes
// macOS leaves in its symbolic hot key preferences.

import Testing

@testable import PitattoCore

@Suite("System Desktop shortcut")
struct SystemSpaceShortcutTests {

  private let controlLeft = SystemSpaceShortcut(keyCode: KeyCode.leftArrow, flags: 0x84_0000)
  private let controlRight = SystemSpaceShortcut(keyCode: KeyCode.rightArrow, flags: 0x84_0000)

  @Test("No preferences at all means the shipped ⌃← and ⌃→")
  func noPreferencesMeansTheShippedKeys() {
    #expect(SystemSpaceShortcut.resolve(.left, in: nil) == controlLeft)
    #expect(SystemSpaceShortcut.resolve(.right, in: [:]) == controlRight)
  }

  @Test("An entry holding only enabled means the shipped key")
  func anEntryWithOnlyEnabledMeansTheShippedKey() {
    #expect(SystemSpaceShortcut.resolve(.left, in: ["79": ["enabled": true]]) == controlLeft)
  }

  @Test("A turned-off shortcut gives no key")
  func aTurnedOffShortcutGivesNoKey() {
    #expect(SystemSpaceShortcut.resolve(.right, in: ["81": ["enabled": false]]) == nil)
    #expect(SystemSpaceShortcut.resolve(.left, in: ["81": ["enabled": false]]) == controlLeft)
  }

  @Test("A key the person changed is the one pressed")
  func aChangedKeyIsTheOnePressed() {
    let hotKeys: [String: Any] = [
      "79": [
        "enabled": true,
        "value": ["parameters": [65535, 0x7B, 0x14_0000], "type": "standard"],
      ]
    ]
    #expect(
      SystemSpaceShortcut.resolve(.left, in: hotKeys)
        == SystemSpaceShortcut(keyCode: KeyCode.leftArrow, flags: 0x14_0000))
  }
}

// KeyComboTests.swift
// Verifies which combinations may become a global hot key: the rule the
// recorder applies as a key is pressed, and that a stored blob is held to.

import Foundation
import Testing

@testable import PitattoCore

@Suite("Key combo")
struct KeyComboTests {

  @Test(
    "At least one of ⌃⌥⌘ makes a global hot key; a bare key or ⇧ alone does not",
    arguments: [
      ([.control], true), ([.option], true), ([.command], true), ([.shift, .command], true),
      ([], false), ([.shift], false),
    ] as [(KeyCombo.Modifiers, Bool)])
  func requiresAGlobalModifier(_ modifiers: KeyCombo.Modifiers, _ expected: Bool) {
    let combo = KeyCombo(keyCode: KeyCode.leftArrow, modifiers: modifiers)
    #expect(combo.hasGlobalModifier == expected)
  }

  @Test("A hand-edited blob with no modifiers decodes, and is refused as a hot key")
  func refusesABareKeyFromStorage() throws {
    let combo = try JSONDecoder().decode(
      KeyCombo.self, from: Data(#"{"keyCode":123,"modifiers":0}"#.utf8))
    #expect(combo.modifiers.isEmpty)
    #expect(!combo.hasGlobalModifier)
  }
}

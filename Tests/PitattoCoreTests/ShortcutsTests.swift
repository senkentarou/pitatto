// ShortcutsTests.swift
// Verifies the conflict the app has to catch itself: two commands bound to one
// combination, which macOS registers without complaint and then delivers to
// only one of them.

import Testing

@testable import PitattoCore

@Suite("Shortcuts")
struct ShortcutsTests {

  private let combo = KeyCombo(keyCode: KeyCode.space, modifiers: [.option])
  private let left = SnapCommand(action: .left)
  private let right = SnapCommand(action: .right)
  private let leftHalf = SnapCommand(action: .left, size: .oneHalf)

  @Test("The shipped shortcuts hold no duplicate")
  func theDefaultsHoldNoDuplicate() {
    #expect(Shortcuts.default.duplicatedCommands().isEmpty)
  }

  @Test("Two commands on one combination are both reported")
  func twoCommandsOnOneComboAreBothReported() {
    var shortcuts = Shortcuts.default
    shortcuts[left] = combo
    shortcuts[right] = combo
    #expect(shortcuts.duplicatedCommands() == [left, right])
  }

  @Test("Three commands on one combination are all reported")
  func threeCommandsOnOneComboAreAllReported() {
    var shortcuts = Shortcuts([:])
    shortcuts[left] = combo
    shortcuts[right] = combo
    shortcuts[leftHalf] = combo
    #expect(shortcuts.duplicatedCommands() == [left, right, leftHalf])
  }

  @Test("Commands with no key do not collide with each other")
  func unboundCommandsDoNotCollide() {
    var shortcuts = Shortcuts([:])
    shortcuts[left] = nil
    shortcuts[right] = nil
    #expect(shortcuts.duplicatedCommands().isEmpty)
  }

  @Test("The other holder of a combination is found, and a command never holds against itself")
  func theOtherHolderIsFound() {
    var shortcuts = Shortcuts([:])
    shortcuts[left] = combo
    #expect(shortcuts.command(holding: combo, otherThan: right) == left)
    #expect(shortcuts.command(holding: combo, otherThan: left) == nil)
    #expect(
      shortcuts.command(
        holding: KeyCombo(keyCode: KeyCode.tab, modifiers: [.option]), otherThan: right)
        == nil)
  }
}

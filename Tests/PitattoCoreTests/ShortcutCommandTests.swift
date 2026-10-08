// ShortcutCommandTests.swift
// Verifies the full set of bindable commands and the ids the Desktop moves are
// stored under, next to the snap ids an older blob already uses.

import Testing

@testable import PitattoCore

@Suite("Shortcut command")
struct ShortcutCommandTests {

  @Test("Every snap command comes first, then the two Desktop moves")
  func theSnapCommandsComeFirst() {
    #expect(ShortcutCommand.allCases.count == SnapCommand.allCases.count + 2)
    #expect(
      Array(ShortcutCommand.allCases.prefix(SnapCommand.allCases.count))
        == SnapCommand.allCases.map(ShortcutCommand.snap))
    #expect(ShortcutCommand.allCases.suffix(2) == [.moveToSpace(.left), .moveToSpace(.right)])
    #expect(Set(ShortcutCommand.allCases.map(\.id)).count == ShortcutCommand.allCases.count)
  }

  @Test("A snap keeps its own id, and a Desktop move is stored under space.<direction>")
  func idsAreTheStoredSpellings() {
    #expect(ShortcutCommand.snap(SnapCommand(action: .left, size: .oneHalf)).id == "left.1/2")
    #expect(ShortcutCommand.moveToSpace(.left).id == "space.left")
    #expect(ShortcutCommand.moveToSpace(.right).id == "space.right")
  }

  @Test("Every id reads back as the command it came from", arguments: ShortcutCommand.allCases)
  func everyIdReadsBackAsTheCommandItCameFrom(_ command: ShortcutCommand) {
    #expect(ShortcutCommand(id: command.id) == command, "\(command.id)")
  }

  @Test("An id outside the set is refused")
  func anIdOutsideTheSetIsRefused() {
    #expect(ShortcutCommand(id: "space") == nil)
    #expect(ShortcutCommand(id: "space.up") == nil)
    #expect(ShortcutCommand(id: "space.left.1/2") == nil)
  }
}

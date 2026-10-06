// SnapCommandTests.swift
// Verifies what a shortcut can be bound to: the twenty commands, and the ids
// they are stored under — which are the saved format, so an older blob written
// when there were only five has to keep reaching its keys.

import Testing

@testable import PitattoCore

@Suite("Snap command")
struct SnapCommandTests {

  @Test("There is one command per direction and size, and no two share an id")
  func thereIsOneCommandPerDirectionAndSize() {
    #expect(SnapCommand.allCases.count == 20, "5 cycling, plus 5 actions × 3 sizes")
    #expect(Set(SnapCommand.allCases).count == SnapCommand.allCases.count, "no repeats")
    #expect(
      Set(SnapCommand.allCases.map(\.id)).count == SnapCommand.allCases.count, "no repeated ids")
  }

  @Test("The cycling commands come first")
  func theCyclingCommandsComeFirst() {
    #expect(
      SnapCommand.allCases.prefix(5).map(\.id) == ["maximize", "left", "right", "top", "bottom"])
  }

  @Test("An action's commands are its cycling key, then its sizes in cycle order")
  func anActionsCommandsFollowTheCycle() {
    #expect(
      SnapCommand.commands(for: .left).map(\.id) == ["left", "left.1/2", "left.1/4", "left.3/4"])
    #expect(
      SnapCommand.commands(for: .maximize).map(\.id) == [
        "maximize", "maximize.margin0", "maximize.margin64", "maximize.margin24",
      ])
  }

  /// These spellings are the keys bindings are stored under. The cycling ones
  /// match the field names used before sizes existed, which is what lets a
  /// blob from that version be read with no migration.
  @Test("The ids are the stored spellings")
  func idsAreTheStoredSpellings() {
    #expect(SnapCommand(action: .left).id == "left")
    #expect(SnapCommand(action: .left, size: .oneHalf).id == "left.1/2")
    #expect(SnapCommand(action: .bottom, size: .threeQuarters).id == "bottom.3/4")
    #expect(SnapCommand(action: .maximize, size: .whole).id == "maximize.margin0")
    #expect(SnapCommand(action: .maximize, size: .smallMargin).id == "maximize.margin24")
  }

  @Test("Every id reads back as the command it came from", arguments: SnapCommand.allCases)
  func everyIdReadsBackAsTheCommandItCameFrom(_ command: SnapCommand) {
    #expect(SnapCommand(id: command.id) == command, "\(command.id)")
  }

  @Test("An id outside the set is refused")
  func anIdOutsideTheSetIsRefused() {
    #expect(SnapCommand(id: "") == nil)
    #expect(SnapCommand(id: "sideways") == nil)
    #expect(SnapCommand(id: "left.2/3") == nil, "not a step of the cycle")
    #expect(SnapCommand(id: "maximize.1/2") == nil, "not a step of maximize")
    #expect(SnapCommand(id: "left.margin24") == nil, "margins belong to maximize only")
    #expect(SnapCommand(id: "maximize.7/8") == nil, "an earlier step that is gone")
  }
}

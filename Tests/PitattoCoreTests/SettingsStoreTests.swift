// SettingsStoreTests.swift
// Verifies that the settings survive a relaunch, that a blob from an older
// version keeps its shortcuts and moves the shipped ⌥⌃ keys to ⌃⌘ once, and
// that a blob the app cannot read falls back to the shipped defaults.

import Foundation
import Testing

@testable import PitattoCore

@Suite("Settings store")
@MainActor
final class SettingsStoreTests {

  /// A throwaway suite, named so two tests running at once never share one.
  private let suiteName: String
  private let defaults: UserDefaults

  init() throws {
    suiteName = "pitatto.tests.\(UUID().uuidString)"
    defaults = try #require(UserDefaults(suiteName: suiteName))
  }

  deinit {
    UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
  }

  @Test("A fresh Mac gets the shipped defaults")
  func aFreshMacGetsTheShippedDefaults() {
    #expect(SettingsStore(defaults: defaults).load() == .default)
  }

  @Test("Settings survive a relaunch")
  func settingsSurviveARelaunch() {
    var settings = Settings.default
    settings.shortcuts[SnapCommand(action: .right)] = KeyCombo(
      keyCode: KeyCode.downArrow, modifiers: [.command, .shift])
    settings.shortcuts[SnapCommand(action: .left, size: .oneQuarter)] = KeyCombo(
      keyCode: KeyCode.leftArrow, modifiers: [.command, .shift])

    SettingsStore(defaults: defaults).save(settings)

    #expect(SettingsStore(defaults: defaults).load() == settings)
  }

  /// A blob written before top and bottom existed, while the step sequence and
  /// the login item were still stored. Three shapes have to survive at once:
  /// an unknown key is ignored, a missing cycling key falls back to the shipped
  /// combo, and a sized command nobody has bound stays unbound.
  ///
  /// The fallback is what matters. `load` turns any decoding error into "use
  /// the defaults for everything", so one missing key would have cost the
  /// person every shortcut they had set.
  @Test("A blob from before top and bottom existed keeps its shortcuts")
  func aBlobFromBeforeTopAndBottomExistedKeepsItsShortcuts() {
    let stored = """
      {"launchAtLogin":true,"fractions":["1/2","1/3","1/4"],\
      "shortcuts":{"maximize":{"keyCode":36,"modifiers":3},\
      "left":{"keyCode":123,"modifiers":3},"right":{"keyCode":125,"modifiers":12}}}
      """
    defaults.set(
      Data(stored.replacingOccurrences(of: "\n", with: "").utf8),
      forKey: SettingsStore.defaultsKey)

    let loaded = SettingsStore(defaults: defaults).load()
    #expect(
      loaded.shortcuts[SnapCommand(action: .right)]
        == KeyCombo(keyCode: KeyCode.downArrow, modifiers: [.command, .shift]))
    for action in SnapAction.allCases {
      let command = SnapCommand(action: action)
      #expect(loaded.shortcuts[command] != nil, "\(command.id) has to reach a key")
    }
    #expect(
      loaded.shortcuts[SnapCommand(action: .top)] == Shortcuts.default[SnapCommand(action: .top)],
      "the key was not in the blob")
    #expect(
      loaded.shortcuts[SnapCommand(action: .left, size: .oneQuarter)] == nil,
      "a sized command nobody bound stays unbound")
  }

  /// A blob from before the ⌃⌘ defaults: maximize and left are still on the
  /// shipped ⌥⌃ keys, right was changed by hand, and a sized command was bound
  /// to ⌥⌃ by hand.
  @Test("A blob from before the ⌃⌘ defaults moves only the shipped ⌥⌃ keys")
  func aBlobFromBeforeTheControlCommandDefaultsMovesOnlyTheShippedKeys() {
    let stored = """
      {"shortcuts":{"maximize":{"keyCode":36,"modifiers":3},\
      "left":{"keyCode":123,"modifiers":3},"right":{"keyCode":124,"modifiers":12},\
      "left.1/4":{"keyCode":123,"modifiers":7}}}
      """
    defaults.set(
      Data(stored.replacingOccurrences(of: "\n", with: "").utf8),
      forKey: SettingsStore.defaultsKey)

    let loaded = SettingsStore(defaults: defaults).load()
    for action in [SnapAction.maximize, .left, .top, .bottom] {
      let command = SnapCommand(action: action)
      #expect(loaded.shortcuts[command] == Shortcuts.default[command], "\(command.id)")
    }
    #expect(
      loaded.shortcuts[SnapCommand(action: .right)]
        == KeyCombo(keyCode: KeyCode.rightArrow, modifiers: [.command, .shift]))
    #expect(
      loaded.shortcuts[SnapCommand(action: .left, size: .oneQuarter)]
        == KeyCombo(keyCode: KeyCode.leftArrow, modifiers: [.option, .control, .shift]))
  }

  /// The move happens once. A ⌥⌃ key chosen after it is the person's choice.
  @Test("A ⌥⌃ key saved after the move stays ⌥⌃")
  func anOptionControlKeySavedAfterTheMoveStays() {
    let combo = KeyCombo(keyCode: KeyCode.leftArrow, modifiers: [.option, .control])
    var settings = Settings.default
    settings.shortcuts[SnapCommand(action: .left)] = combo
    SettingsStore(defaults: defaults).save(settings)

    #expect(SettingsStore(defaults: defaults).load().shortcuts[SnapCommand(action: .left)] == combo)
  }

  /// The shortcuts are written as a JSON object keyed by the command id, not
  /// as a flat array of alternating keys and values — which is what a
  /// dictionary keyed by anything but a String would encode as.
  @Test("Shortcuts are stored as an object keyed by the command id")
  func shortcutsAreStoredAsAnObjectKeyedByCommand() throws {
    var shortcuts = Shortcuts([:])
    shortcuts[SnapCommand(action: .left, size: .threeQuarters)] = KeyCombo(
      keyCode: KeyCode.leftArrow, modifiers: [.option, .control])

    // Sorted, because the assertion is about the shape — an object keyed by the
    // command id — and not about the order a keyed container happens to emit.
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let text = String(decoding: try encoder.encode(shortcuts), as: UTF8.self)
    #expect(text == #"{"left.3\/4":{"keyCode":123,"modifiers":3}}"#)
  }

  @Test("A blob the app cannot read falls back to the defaults, and is left in place")
  func aBlobTheAppCannotReadFallsBackToTheDefaults() {
    defaults.set(Data("not json".utf8), forKey: SettingsStore.defaultsKey)
    #expect(SettingsStore(defaults: defaults).load() == .default)
    #expect(defaults.data(forKey: SettingsStore.defaultsKey) != nil)
  }

  @Test("The shipped shortcuts are the README ones")
  func theShippedShortcutsAreTheReadmeOnes() {
    let shortcuts = Shortcuts.default
    #expect(shortcuts[SnapCommand(action: .maximize)]?.modifierSymbols == "⌃⌘")
    #expect(shortcuts[SnapCommand(action: .maximize)]?.namedKeyLabel == "↩")
    #expect(shortcuts[SnapCommand(action: .left)]?.namedKeyLabel == "←")
    #expect(shortcuts[SnapCommand(action: .right)]?.namedKeyLabel == "→")
    #expect(shortcuts[SnapCommand(action: .top)]?.namedKeyLabel == "↑")
    #expect(shortcuts[SnapCommand(action: .bottom)]?.namedKeyLabel == "↓")
  }

  /// Every size is reachable by cycling already, so a default for each would
  /// spend fifteen combinations to save presses nobody has asked to save.
  @Test(
    "The sized commands ship with no key",
    arguments: SnapCommand.allCases.filter { $0.size != nil })
  func theSizedCommandsShipWithNoKey(_ command: SnapCommand) {
    #expect(Shortcuts.default[command] == nil, "\(command.id)")
  }

  /// Keyed on the position in `allCases`, not on anything about the name: a
  /// key derived from the id has to stay unique as commands are added, and
  /// silently stops testing anything the day two of them collide.
  @Test("Every command reaches its own shortcut")
  func everyCommandReachesItsOwnShortcut() {
    var shortcuts = Shortcuts.default
    for (index, command) in SnapCommand.allCases.enumerated() {
      shortcuts[command] = KeyCombo(keyCode: UInt16(index), modifiers: [.command])
    }
    for (index, command) in SnapCommand.allCases.enumerated() {
      #expect(shortcuts[command]?.keyCode == UInt16(index))
    }
  }

  @Test("Clearing a command leaves it unbound")
  func clearingACommandLeavesItUnbound() {
    var shortcuts = Shortcuts.default
    let command = SnapCommand(action: .left)
    #expect(shortcuts[command] != nil)
    shortcuts[command] = nil
    #expect(shortcuts[command] == nil)
  }

  /// The decoder fills in a cycling key the blob does not mention, so a key the
  /// person cleared has to be written down as cleared, or the shipped one is
  /// back on the next launch.
  @Test("A cleared cycling key stays cleared after a relaunch")
  func aClearedCyclingKeyStaysClearedAfterARelaunch() {
    var settings = Settings.default
    settings.shortcuts[SnapCommand(action: .left)] = nil
    SettingsStore(defaults: defaults).save(settings)

    let reloaded = SettingsStore(defaults: defaults).load()
    #expect(reloaded.shortcuts[SnapCommand(action: .left)] == nil)
    #expect(reloaded.shortcuts[SnapCommand(action: .right)] != nil, "only the cleared key is gone")
  }

  @Test("A cleared key is stored as null")
  func aClearedKeyIsStoredAsNull() throws {
    var shortcuts = Shortcuts([:])
    shortcuts[SnapCommand(action: .left)] = nil

    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let text = String(decoding: try encoder.encode(shortcuts), as: UTF8.self)
    #expect(text == #"{"left":null}"#)
  }
}

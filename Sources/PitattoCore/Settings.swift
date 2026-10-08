// Settings.swift
// Everything the app remembers between launches.

import Foundation

/// What the settings window edits.
///
/// Nothing about a window is stored: where a window sits is the window's
/// business, and the repeat-press judgement reads it back from the window
/// itself rather than from a remembered copy. Nor is the login item: macOS
/// holds that switch, and the app reads it back rather than remembering it.
public struct Settings: Equatable, Codable, Sendable {
  public var shortcuts: Shortcuts

  public init(shortcuts: Shortcuts = .default) {
    self.shortcuts = shortcuts
  }

  public static let `default` = Settings()

  /// Written into every blob so `init(from:)` can tell which shipped keys the
  /// blob was saved under. A blob without it predates the ⌃⌘ defaults.
  static let revision = 1

  private enum CodingKeys: String, CodingKey {
    case shortcuts
    case revision
  }

  /// A blob from before the ⌃⌘ defaults gets the cycling keys it still holds
  /// at the old ⌥⌃ moved to ⌃⌘, once. Comparing on every load instead would
  /// undo a ⌥⌃ key the person picks on purpose after the move.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    var shortcuts = try container.decode(Shortcuts.self, forKey: .shortcuts)
    if try container.decodeIfPresent(Int.self, forKey: .revision) == nil {
      shortcuts.moveCyclingKeysOffOptionControl()
    }
    self.shortcuts = shortcuts
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(shortcuts, forKey: .shortcuts)
    try container.encode(Self.revision, forKey: .revision)
  }
}

/// Every shortcut, keyed by the command it runs.
///
/// A dictionary rather than a field each: there are twenty commands and
/// fifteen of them ship with no key at all, so a field each would be twenty
/// fields and no way to spell "nothing". A command is unbound when its key is
/// absent or holds `nil`; the two are told apart only by `init(from:)`.
///
/// Keyed by `String`, not by `SnapCommand`: `JSONEncoder` writes a dictionary
/// with any other key type as a flat array of alternating keys and values,
/// which is neither readable nor stable to hand-edit.
public struct Shortcuts: Equatable, Codable, Sendable {
  private var combos: [String: KeyCombo?]

  public init(_ combos: [String: KeyCombo]) {
    self.combos = combos.mapValues { Optional($0) }
  }

  /// nil when nothing is bound to `command`.
  public subscript(command: SnapCommand) -> KeyCombo? {
    get { combos[command.id] ?? nil }
    set { combos[command.id] = .some(newValue) }
  }

  /// The commands bound to a combination another command also holds.
  ///
  /// macOS registers both without complaint and then delivers the press to one
  /// of them, so this is the conflict the app has to catch itself. Commands
  /// with no key are skipped rather than compared: most of them ship that way,
  /// and treating "nothing" as a combination would make every one of them
  /// collide with every other.
  public func duplicatedCommands() -> Set<SnapCommand> {
    var seen: [KeyCombo: SnapCommand] = [:]
    var duplicated: Set<SnapCommand> = []
    for command in SnapCommand.allCases {
      guard let combo = self[command] else { continue }
      if let first = seen[combo] {
        duplicated.insert(first)
        duplicated.insert(command)
      } else {
        seen[combo] = command
      }
    }
    return duplicated
  }

  /// The command other than `command` that `combo` is bound to, if there is one.
  public func command(holding combo: KeyCombo, otherThan command: SnapCommand) -> SnapCommand? {
    SnapCommand.allCases.first { $0 != command && self[$0] == combo }
  }

  /// ⌃⌘↩ / ⌃⌘← / ⌃⌘→ / ⌃⌘↑ / ⌃⌘↓, so the app works with no setup. Not ⌥⌃,
  /// which is left free for other tools, and not ⌥⌘, whose arrows switch tabs
  /// in browsers and editors.
  ///
  /// The sized commands ship unbound. Every size is already reachable by
  /// cycling, so a default for each would spend fifteen key combinations to
  /// save presses nobody has asked to save yet.
  public static let `default` = Shortcuts([
    SnapCommand(action: .maximize).id: KeyCombo(
      keyCode: KeyCode.return, modifiers: [.control, .command]),
    SnapCommand(action: .left).id: KeyCombo(
      keyCode: KeyCode.leftArrow, modifiers: [.control, .command]),
    SnapCommand(action: .right).id: KeyCombo(
      keyCode: KeyCode.rightArrow, modifiers: [.control, .command]),
    SnapCommand(action: .top).id: KeyCombo(
      keyCode: KeyCode.upArrow, modifiers: [.control, .command]),
    SnapCommand(action: .bottom).id: KeyCombo(
      keyCode: KeyCode.downArrow, modifiers: [.control, .command]),
  ])

  /// A cycling command the blob has no entry for gets the shipped key; a sized
  /// command stays unbound either way.
  ///
  /// The asymmetry is what makes an upgrade safe. A blob written before the
  /// sized commands existed holds exactly the five cycling keys, and a blob
  /// written before top and bottom existed holds three — both have to come
  /// back with every direction working. A cycling key the person cleared is
  /// stored as an explicit `null`, so only an absent key means "written by an
  /// older version".
  public init(from decoder: any Decoder) throws {
    var combos = try decoder.singleValueContainer().decode([String: KeyCombo?].self)
    for action in SnapAction.allCases {
      let cycling = SnapCommand(action: action)
      if combos[cycling.id] == nil {
        combos[cycling.id] = .some(Shortcuts.default[cycling])
      }
    }
    self.combos = combos
  }

  /// Each cycling command still on the shipped ⌥⌃ key gets the shipped ⌃⌘ one.
  /// A cycling key the person changed, and every sized command, stay as they are.
  mutating func moveCyclingKeysOffOptionControl() {
    for action in SnapAction.allCases {
      let cycling = SnapCommand(action: action)
      guard let shipped = Shortcuts.default[cycling] else { continue }
      if self[cycling] == KeyCombo(keyCode: shipped.keyCode, modifiers: [.option, .control]) {
        self[cycling] = shipped
      }
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(combos)
  }
}

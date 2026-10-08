// ShortcutCommand.swift
// Everything a shortcut can be bound to: a snap, or a move to the next Desktop.

import Foundation

/// One assignable shortcut.
///
/// Sending a window to another Desktop sets no frame, so it stays out of
/// `SnapAction`, whose every case has a cycle of sizes and an edge to sit
/// against.
public enum ShortcutCommand: Hashable, Sendable {
  case snap(SnapCommand)
  case moveToSpace(SpaceDirection)

  /// Every snap command in its own order, then the two Desktop moves. The
  /// order is what the hot key identifiers are derived from.
  public static let allCases: [ShortcutCommand] =
    SnapCommand.allCases.map(ShortcutCommand.snap)
    + SpaceDirection.allCases.map(ShortcutCommand.moveToSpace)

  /// `SnapCommand.id` for a snap, `space.left` / `space.right` for a move.
  /// The key a binding is stored under, so part of the saved format.
  public var id: String {
    switch self {
    case .snap(let command): return command.id
    case .moveToSpace(let direction): return "space.\(direction.rawValue)"
    }
  }

  public init?(id: String) {
    if let command = SnapCommand(id: id) {
      self = .snap(command)
      return
    }
    guard
      id.hasPrefix("space."),
      let direction = SpaceDirection(rawValue: String(id.dropFirst("space.".count)))
    else { return nil }
    self = .moveToSpace(direction)
  }
}

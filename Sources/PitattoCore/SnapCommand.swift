// SnapCommand.swift
// What one shortcut does: a direction, and sometimes the exact size too.

import Foundation

/// One assignable shortcut.
///
/// A direction on its own cycles: each press takes the next step of
/// `SnapCycle.steps(for:)`, so reaching a width means counting presses. A direction
/// paired with a size goes straight there however many times it is pressed.
/// Both forms exist because they answer different questions — "a bit narrower"
/// and "one third, now".
public struct SnapCommand: Hashable, Sendable {
  public let action: SnapAction
  /// nil is the cycling form.
  public let size: SnapSize?

  public init(action: SnapAction, size: SnapSize? = nil) {
    self.action = action
    self.size = size
  }

  /// The cycling command for `action`, then one per size, in the order the
  /// settings grid draws them.
  public static func commands(for action: SnapAction) -> [SnapCommand] {
    [SnapCommand(action: action)]
      + SnapCycle.steps(for: action).map { SnapCommand(action: action, size: $0) }
  }

  /// The cycling commands first, then every direction against each of its
  /// own sizes.
  public static let allCases: [SnapCommand] =
    SnapAction.allCases.map { SnapCommand(action: $0) }
    + SnapAction.allCases.flatMap { commands(for: $0).dropFirst() }

  /// `left` for the cycling form, `left.1/2` for a sized one.
  ///
  /// This is the key a binding is stored under, so it is part of the saved
  /// format — and the cycling spellings are the ones the five named fields
  /// used before there were sizes, which is what lets an older blob be read
  /// with no migration.
  public var id: String {
    guard let size else { return action.rawValue }
    return "\(action.rawValue).\(size)"
  }

  public init?(id: String) {
    let parts = id.split(separator: ".", maxSplits: 1)
    guard let name = parts.first, let action = SnapAction(rawValue: String(name)) else {
      return nil
    }
    guard parts.count == 2 else {
      self.init(action: action)
      return
    }
    guard let size = SnapCycle.steps(for: action).first(where: { $0.description == parts[1] })
    else { return nil }
    self.init(action: action, size: size)
  }
}

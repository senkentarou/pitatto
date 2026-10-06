// SnapAction.swift
// The five things a Pitatto shortcut can do.
//
// The settings window names them in Japanese, and comments elsewhere use those
// names: 最大化 is maximize; 左に寄せる, 右に寄せる, 上に寄せる and 下に寄せる are
// left, right, top and bottom; 寄せる on its own is any of the four edges.

import Foundation

/// There is no corner: a corner needs two fractions at once
/// and the step sequence holds one.
///
/// Declaration order is the order the settings screen draws the rows in.
public enum SnapAction: String, CaseIterable, Codable, Sendable {
  case maximize
  case left
  case right
  /// Named for the edge it sits against, like `left` and `right` — not for the
  /// arrow key that reaches it.
  case top
  case bottom
}

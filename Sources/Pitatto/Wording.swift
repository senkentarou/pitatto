// Wording.swift
// How the settings window names an action, a size and a command. The recorder
// fields read from here too, so a row and its fields never disagree.

import PitattoCore

/// `左に寄せる` for a cycling command, `左に寄せる 1/2` for a sized one.
func label(for command: SnapCommand) -> String {
  guard let size = command.size else { return label(for: command.action) }
  return "\(label(for: command.action)) \(label(for: size))"
}

/// `1/2` for a fraction, `余白 24pt` for a margin.
func label(for size: SnapSize) -> String {
  switch size {
  case .fraction: return size.description
  case .whole: return "全体"
  case .margin(let points): return "余白 \(points)pt"
  }
}

func label(for action: SnapAction) -> String {
  switch action {
  case .maximize: return "最大化"
  case .left: return "左に寄せる"
  case .right: return "右に寄せる"
  case .top: return "上に寄せる"
  case .bottom: return "下に寄せる"
  }
}

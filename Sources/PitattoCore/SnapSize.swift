// SnapSize.swift
// How large a snapped window is: a fraction of the work area against an edge,
// or a margin left clear around a maximized one.

import Foundation

/// One step of the cycle a repeated press walks through.
public enum SnapSize: Hashable, Sendable {
  /// An edge snap (寄せる): the width or height, measured from the edge.
  case fraction(numerator: Int, denominator: Int)
  /// Maximize (最大化): points left clear on every side, so the window stays
  /// centred and the gap is the same on a laptop as on a wide display.
  case margin(Int)

  public static let oneQuarter = SnapSize.fraction(numerator: 1, denominator: 4)
  public static let oneHalf = SnapSize.fraction(numerator: 1, denominator: 2)
  public static let threeQuarters = SnapSize.fraction(numerator: 3, denominator: 4)
  public static let whole = SnapSize.margin(0)
  public static let smallMargin = SnapSize.margin(24)
  public static let largeMargin = SnapSize.margin(64)
}

extension SnapSize: CustomStringConvertible {
  /// `1/2` or `margin24`, which is how a step reads in a trace and how a sized
  /// command is stored.
  public var description: String {
    switch self {
    case .fraction(let numerator, let denominator): return "\(numerator)/\(denominator)"
    case .margin(let points): return "margin\(points)"
    }
  }
}

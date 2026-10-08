// SpaceDirection.swift
// Which neighbouring Desktop a window is sent to.

import Foundation

/// The Desktops (Spaces) sit in a row in Mission Control, so a neighbour is
/// one to the left or one to the right.
public enum SpaceDirection: String, CaseIterable, Sendable {
  case left
  case right
}

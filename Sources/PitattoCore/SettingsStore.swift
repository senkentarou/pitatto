// SettingsStore.swift
// Reads and writes the settings blob. UserDefaults is injected so tests run
// against a throwaway suite instead of the real user's preferences.

import Foundation

/// Reads and writes the settings blob.
@MainActor
public final class SettingsStore {
  /// One key holds the whole Codable value.
  public static let defaultsKey = "settings"

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// Returns the stored settings, or the defaults if nothing is stored or the
  /// stored blob cannot be decoded. A corrupt blob is left in place rather than
  /// erased; the next `save` overwrites it.
  public func load() -> Settings {
    guard
      let data = defaults.data(forKey: Self.defaultsKey),
      let decoded = try? JSONDecoder().decode(Settings.self, from: data)
    else { return .default }
    return decoded
  }

  public func save(_ settings: Settings) {
    guard let data = try? JSONEncoder().encode(settings) else { return }
    defaults.set(data, forKey: Self.defaultsKey)
  }
}

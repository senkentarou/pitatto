// UpdateConfig.swift
// Where the updater looks and what it will trust.

import Foundation

enum UpdateConfig {
  static let latestReleaseURL = URL(
    string: "https://api.github.com/repos/senkentarou/pitatto/releases/latest")!
  static let releasesPageURL = URL(
    string: "https://github.com/senkentarou/pitatto/releases")!
  /// The Developer ID team the replacement bundle must be signed by. Pinning
  /// the team is what makes the download safe to run: HTTPS proves the route,
  /// not the signer.
  ///
  /// A fork that ships its own releases has to change this together with
  /// `latestReleaseURL`. Changing only the URL leaves every download rejected
  /// as signed by another team, which reads as a broken updater rather than as
  /// a setting that was missed.
  static let teamID = "U2H8U2TN85"
  /// Release assets are named `Pitatto-<version>.zip` by `make release`.
  static let assetPrefix = "Pitatto-"
  static let userAgent = "Pitatto"
}

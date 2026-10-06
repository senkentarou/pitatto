// ReleaseFeedTests.swift
// Verifies that a GitHub /releases/latest body becomes the release the update
// flow can act on, and that a body it cannot trust is refused by name.

import Foundation
import Testing

@testable import PitattoCore

@Suite("Release feed")
struct ReleaseFeedTests {

  private let prefix = "Pitatto-"

  /// The fields of a real `/releases/latest` response that the parser reads,
  /// plus one asset it must ignore. The checksum comes first so that picking
  /// the zip takes the suffix into account, not just the order GitHub happens
  /// to list assets in.
  private func body(
    tag: String = "v1.1.0",
    assets: String =
      """
    [
      { "name": "Pitatto-1.1.0.zip.sha256",
        "browser_download_url": "https://example.com/Pitatto-1.1.0.zip.sha256",
        "size": 96 },
      { "name": "Pitatto-1.1.0.zip",
        "browser_download_url": "https://example.com/Pitatto-1.1.0.zip",
        "size": 4194304 }
    ]
    """
  ) -> Data {
    Data(
      """
      {
        "tag_name": "\(tag)",
        "name": "Pitatto 1.1.0",
        "body": "- 押して離したときの判定を修正しました\\n- 表示のちらつきを修正しました",
        "html_url": "https://github.com/senkentarou/pitatto/releases/tag/\(tag)",
        "published_at": "2026-09-20T02:30:00Z",
        "assets": \(assets)
      }
      """.utf8)
  }

  @Test("A release with a Pitatto-*.zip asset is read whole")
  func readsARelease() throws {
    let release = try ReleaseFeed.parseLatest(body(), assetPrefix: prefix)

    #expect(release.version == SemanticVersion(major: 1, minor: 1, patch: 0))
    #expect(release.assetName == "Pitatto-1.1.0.zip")
    #expect(release.assetSize == 4_194_304)
    #expect(release.downloadURL.absoluteString == "https://example.com/Pitatto-1.1.0.zip")
    #expect(release.notes.contains("押して離したときの判定を修正しました"))
    // 2026-09-20T02:30:00Z, as the fixture says.
    #expect(release.publishedAt == Date(timeIntervalSince1970: 1_789_871_400))
  }

  @Test("The first Pitatto-*.zip wins and other assets are ignored")
  func picksTheZip() throws {
    let assets =
      """
      [
        { "name": "SHASUMS", "browser_download_url": "https://example.com/SHASUMS", "size": 1 },
        { "name": "Pitatto-1.1.0.zip",
          "browser_download_url": "https://example.com/Pitatto-1.1.0.zip", "size": 2 }
      ]
      """
    let release = try ReleaseFeed.parseLatest(body(assets: assets), assetPrefix: prefix)

    #expect(release.assetName == "Pitatto-1.1.0.zip")
  }

  @Test("A release built for another app has no asset we can install")
  func refusesAForeignAsset() {
    let assets =
      """
      [
        { "name": "SomeOtherApp-1.1.0.zip",
          "browser_download_url": "https://example.com/SomeOtherApp-1.1.0.zip", "size": 1 }
      ]
      """
    #expect(throws: ReleaseFeedError.noAsset) {
      try ReleaseFeed.parseLatest(body(assets: assets), assetPrefix: prefix)
    }
  }

  @Test("A release with no assets at all is refused")
  func refusesNoAssets() {
    #expect(throws: ReleaseFeedError.noAsset) {
      try ReleaseFeed.parseLatest(body(assets: "[]"), assetPrefix: prefix)
    }
  }

  @Test("A tag that is not a version is refused, and says which tag")
  func refusesAnUnreadableTag() {
    #expect(throws: ReleaseFeedError.unreadableTag("nightly")) {
      try ReleaseFeed.parseLatest(body(tag: "nightly"), assetPrefix: prefix)
    }
  }

  @Test("A body missing tag_name is refused, and says which field")
  func refusesAMissingField() {
    let data = Data(#"{"html_url": "https://example.com", "assets": []}"#.utf8)
    #expect(throws: ReleaseFeedError.missingField("tag_name")) {
      try ReleaseFeed.parseLatest(data, assetPrefix: prefix)
    }
  }

  @Test("A response that is not JSON is refused")
  func refusesNonJSON() {
    #expect(throws: ReleaseFeedError.notJSON) {
      try ReleaseFeed.parseLatest(Data("<html>rate limited</html>".utf8), assetPrefix: prefix)
    }
  }

  @Test("Only a strictly newer release is offered")
  func offersOnlyNewer() throws {
    let release = try ReleaseFeed.parseLatest(body(), assetPrefix: prefix)

    #expect(release.isNewer(than: SemanticVersion(major: 1, minor: 0, patch: 9)))
    #expect(!release.isNewer(than: SemanticVersion(major: 1, minor: 1, patch: 0)))
    #expect(!release.isNewer(than: SemanticVersion(major: 1, minor: 2, patch: 0)))
  }
}

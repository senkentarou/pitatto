// MenuContent.swift
// The menu bar menu. The fixed items, two more while the permission is missing,
// and one more while a newer release is waiting.

import PitattoCore
import SwiftUI

/// No status heading: once the permission is granted Pitatto has nothing to
/// report — it has no pause and no per-app state — so the heading could only
/// ever read "有効". The states worth saying are the missing permission and a
/// newer release, and each gets its own line only while it holds.
struct MenuContent: View {
  @ObservedObject var controller: AppController
  @ObservedObject var updater: UpdateController

  var body: some View {
    if !controller.isTrusted {
      Button {
      } label: {
        Text("ウィンドウを動かすにはアクセシビリティの許可が必要です")
      }
      .disabled(true)

      Button("アクセシビリティを許可…") { controller.openAccessibilitySettings() }

      Divider()
    }

    if case .available(let release) = updater.phase {
      Button("新しいバージョン \(release.version.description) があります…") {
        controller.openUpdateWindow()
      }

      Divider()
    }

    Button("設定…") { controller.openSettingsWindow() }

    Button("アップデートを確認…") {
      updater.check(userInitiated: true)
      controller.openUpdateWindow()
    }

    Divider()

    Button("Pitatto を終了") { controller.quit() }
      .keyboardShortcut("q", modifiers: .command)
  }
}

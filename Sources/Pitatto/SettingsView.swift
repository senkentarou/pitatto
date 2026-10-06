// SettingsView.swift
// The settings window: a tab bar over 一般, ショートカット and クレジット.

import AppKit
import PitattoCore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var controller: AppController
  @State private var selection: SettingsTab = .general

  /// Fixed, so switching tabs never resizes the window. The height fits the
  /// shortcuts tab; a conflict caption beyond that scrolls inside the page.
  ///
  /// Wide enough that the shortcut grid's four fields each hold "キーを押す…"
  /// without clipping: every field says the same thing, rather than the grid
  /// getting a shorter wording that reads as an instruction to click.
  static let size = CGSize(width: 560, height: 540)

  var body: some View {
    VStack(spacing: 0) {
      SettingsTabBar(
        tabs: SettingsTab.allCases,
        title: \.title,
        symbol: \.symbol,
        selection: $selection
      )
      switch selection {
      case .general:
        SettingsPage { general }
      case .shortcuts:
        SettingsPage { shortcuts }
      case .credits:
        credits
      }
    }
    .frame(width: Self.size.width, height: Self.size.height)
    .background(SettingsChrome.background)
    .ignoresSafeArea()
  }

  // MARK: - 一般

  private var general: some View {
    SettingsCard {
      SettingsRow(title: "ログイン時に起動") {
        Toggle(
          "",
          isOn: Binding(
            get: { controller.launchAtLogin },
            set: { controller.setLaunchAtLogin($0) })
        )
        .labelsHidden()
        .toggleStyle(.switch)
        .accessibilityLabel("ログイン時に起動")
      }

      SettingsRowDivider()

      SettingsRow(
        title: "アクセシビリティ",
        caption: controller.isTrusted ? nil : "ウィンドウを動かすにはアクセシビリティの許可が必要です。許可するまでショートカットは効きません",
        leading: {
          Image(systemName: controller.isTrusted ? "checkmark.circle.fill" : "circle.dashed")
            .foregroundStyle(controller.isTrusted ? Color.green : SettingsChrome.secondaryText)
        },
        control: {
          if controller.isTrusted {
            Text("許可済み")
              .font(SettingsChrome.rowCaptionFont)
              .foregroundStyle(SettingsChrome.secondaryText)
          } else {
            Button("許可…") { controller.openAccessibilitySettings() }
          }
        }
      )
    }
  }

  // MARK: - ショートカット

  /// An action to a row: the cycling key, then its sizes. 最大化 gets a card of
  /// its own because its sizes shrink both sides around the centre while the
  /// edges' sizes are widths, so the two cannot share column headings.
  @ViewBuilder private var shortcuts: some View {
    SettingsSection(
      footer: "サイクルの欄は、同じキーを続けて押すと 全体 → 余白 64pt → 余白 24pt と、"
        + "画面の中央で四辺に余白を空けていきます。全体と余白の欄は、サイクルせずその大きさにします。"
    ) {
      grid(for: [.maximize])
    }
    SettingsSection(
      footer: "サイクルの欄は、同じキーを続けて押すとサイズが 1/2 → 1/4 → 3/4 と変わります。"
        + "1/2・1/4・3/4 の欄は、サイクルせずそのサイズに寄せます。"
        + "欄を押してからキーを押すと変わります。⎋ で取り消し、⌫ か × で割り当てを消します。"
    ) {
      grid(for: [.left, .right, .top, .bottom])
    }
  }

  /// Actions that share one list of sizes, under one header.
  @ViewBuilder private func grid(for actions: [SnapAction]) -> some View {
    SettingsGridHeader(
      titles: ["サイクル"] + SnapCycle.steps(for: actions[0]).map(label(for:)))
    ForEach(Array(actions.enumerated()), id: \.element) { index, action in
      if index > 0 { SettingsRowDivider() }
      let commands = SnapCommand.commands(for: action)
      SettingsGridRow(
        title: label(for: action),
        // The refused keystroke wins the row's one caption, even when a field
        // before it is already red for a key macOS would not take.
        caption: commands.first { controller.rejection?.command == $0 }
          .flatMap(conflictMessage(for:))
          ?? commands.compactMap(conflictMessage(for:)).first
      ) {
        ForEach(commands, id: \.self) { command in
          recorder(for: command)
            .frame(width: SettingsChrome.gridColumnWidth)
        }
      }
    }
  }

  private func recorder(for command: SnapCommand) -> some View {
    ShortcutRecorder(
      command: command,
      combo: controller.settings.shortcuts[command],
      isUnavailable: controller.unavailableShortcuts.contains(command)
        || controller.rejection?.command == command,
      hint: conflictMessage(for: command),
      isRecording: controller.recordingCommand == command,
      onBeginRecording: { controller.beginRecording(for: command) },
      onClear: { controller.clearShortcut(for: command) },
      onFinish: { controller.endRecording(with: $0, for: command) }
    )
  }

  /// The error text under a row: what happened, then what to do about it.
  ///
  /// A refused keystroke comes first, because it is the thing that just
  /// happened. It says the binding is untouched: the field still shows the old
  /// key, and without the sentence that reads as the press having been lost.
  ///
  /// A grid row names the command, not just the action: the four fields share
  /// one caption, so "左に寄せる 1/2" is what tells them apart.
  private func conflictMessage(for command: SnapCommand) -> String? {
    if let rejection = controller.rejection, rejection.command == command {
      let key = KeyLabel.text(for: rejection.combo)
      guard let heldBy = rejection.heldBy else {
        return "\(key) は他のアプリが使っています。割り当ては変えていません"
      }
      return "\(key) は「\(label(for: heldBy))」が使っています。割り当ては変えていません"
    }
    guard
      controller.unavailableShortcuts.contains(command),
      let assigned = controller.settings.shortcuts[command]
    else { return nil }
    return "\(KeyLabel.text(for: assigned)) は今は使えません。別の組み合わせを押してください"
  }

  // MARK: - クレジット

  /// The credits tab: no cards, one centred column like the macOS
  /// About panel.
  private var credits: some View {
    VStack(spacing: 16) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 72, height: 72)
      Text(verbatim: "Pitatto")
        .font(.title)
        .fontWeight(.bold)
        .foregroundStyle(SettingsChrome.primaryText)
      Text("バージョン \(AppVersion.short)")
        .foregroundStyle(SettingsChrome.secondaryText)
      Text(verbatim: "© 2026 Masahiro Senda · Licensed under GPL-3.0")
        .font(.caption)
        .foregroundStyle(SettingsChrome.secondaryText)
      Link(
        "github.com/senkentarou/pitatto",
        destination: URL(string: "https://github.com/senkentarou/pitatto")!
      )
      .font(.caption)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(SettingsChrome.background)
  }
}

enum SettingsTab: CaseIterable {
  case general
  case shortcuts
  case credits

  var title: String {
    switch self {
    case .general: return "一般"
    case .shortcuts: return "ショートカット"
    case .credits: return "クレジット"
    }
  }

  var symbol: String {
    switch self {
    case .general: return "gearshape"
    case .shortcuts: return "keyboard"
    case .credits: return "info.circle"
    }
  }
}

enum AppVersion {
  static let short =
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
}

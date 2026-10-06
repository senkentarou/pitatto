// PitattoApp.swift
// Entry point. A menu bar item and one window, no Dock tile.

import AppKit
import SwiftUI

@main
struct PitattoApp: App {
  @StateObject private var controller = AppController()

  init() {
    let arguments = CommandLine.arguments
    if let index = arguments.firstIndex(of: "--print-frame") {
      // Before any scene is built: this run prints one line and leaves.
      FrameDump.run(argument: arguments.count > index + 1 ? arguments[index + 1] : nil)
    }
  }

  var body: some Scene {
    MenuBarExtra {
      MenuContent(controller: controller, updater: controller.updater)
    } label: {
      MenuBarLabel(controller: controller)
    }
    .menuBarExtraStyle(.menu)

    Window("Pitatto 設定", id: WindowID.settings) {
      SettingsView(controller: controller)
        .onDisappear { controller.settingsWindowDidClose() }
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
    .defaultPosition(.center)

    Window("Pitatto アップデート", id: WindowID.update) {
      UpdateView(updater: controller.updater)
    }
    .windowResizability(.contentSize)
    .defaultPosition(.center)
  }
}

/// The mark in the menu bar, and the app's only always-present view.
///
/// Start-up runs from here rather than an `NSApplicationDelegateAdaptor`
/// because `openWindow` is a SwiftUI environment value: the controller needs a
/// way to show the settings window, and this is the one view guaranteed to
/// exist before anything else does.
private struct MenuBarLabel: View {
  @ObservedObject var controller: AppController
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Image(nsImage: MenuBarIcon.image())
      .accessibilityLabel("Pitatto")
      .onAppear {
        // LSUIElement already keeps the app out of the Dock; setting the policy
        // again covers launches that ignore the plist, such as from a debugger.
        NSApp.setActivationPolicy(.accessory)
        controller.openWindow = { id in openWindow(id: id) }
        controller.start()
      }
  }
}

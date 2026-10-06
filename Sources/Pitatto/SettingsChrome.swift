// SettingsChrome.swift
// Shared look of the settings window: palette, metrics, the tab bar, and the
// card / row building blocks each tab is assembled from.
//
// The screen is deliberately NOT built on SwiftUI's `Form(.grouped)`: grouped
// Form owns its own insets, header typography and separator placement, none of
// which can be pushed to the flatter card look this window wants (a 10pt card
// with a hairline border, a 13pt title over an 11pt caption, and a separator
// that runs the full width of the card). Composing the card out of plain
// containers keeps all of those values in this one file.
//
// Colours are dynamic NSColors rather than asset catalog entries so they
// resolve against whichever NSAppearance the window is running under.

import AppKit
import PitattoCore
import SwiftUI

// MARK: - Tokens

enum SettingsChrome {

  // MARK: Metrics

  static let cardRadius: CGFloat = 10
  static let tabRadius: CGFloat = 10
  static let rowHorizontalPadding: CGFloat = 16
  static let rowVerticalPadding: CGFloat = 14
  static let rowControlSpacing: CGFloat = 16
  /// The label column of a grid row. Wide enough for 左に寄せる at 13pt, and
  /// what is left over at 488pt divides into four fields.
  static let gridLabelWidth: CGFloat = 72
  static let gridColumnSpacing: CGFloat = 8
  /// Fixed, so a column lines up with its title however wide the cap inside it
  /// is. Matches a field at its minimum: nothing here should be wider than the
  /// longest thing it has to say.
  static let gridColumnWidth: CGFloat = 96
  static let cardSpacing: CGFloat = 16
  static let pagePadding: CGFloat = 20
  /// Height reserved for the transparent title bar the tab bar is drawn under.
  /// `SettingsTabBar` is the single place that pays this inset, which is why
  /// the root view ignores the safe area — otherwise the system inset and
  /// this one stack up.
  static let titleBarHeight: CGFloat = 28
  static let tabSize = CGSize(width: 76, height: 50)
  static let tabSpacing: CGFloat = 8

  // MARK: Fonts

  static let rowTitleFont = Font.system(size: 13)
  static let rowCaptionFont = Font.system(size: 11)
  static let tabLabelFont = Font.system(size: 11)

  // MARK: Palette

  /// Page background, behind the cards.
  static let background = dynamic(dark: rgb(0x1C, 0x1C, 0x1E), light: rgb(0xF2, 0xF2, 0xF7))
  /// Card fill, and the tab bar that merges with the title bar.
  static let surface = dynamic(dark: rgb(0x2C, 0x2C, 0x2E), light: rgb(0xFF, 0xFF, 0xFF))
  /// Card border and the hairline between rows.
  static let border = dynamic(dark: rgb(0x38, 0x38, 0x3A), light: rgb(0xD1, 0xD1, 0xD6))
  /// Row titles.
  static let primaryText = dynamic(dark: rgb(0xF5, 0xF5, 0xF7), light: rgb(0x1C, 0x1C, 0x1E))
  /// Row captions.
  static let secondaryText = dynamic(dark: rgb(0x98, 0x98, 0x9D), light: rgb(0x8E, 0x8E, 0x93))
  /// Section headers above a card.
  static let tertiaryText = dynamic(dark: rgb(0x63, 0x63, 0x66), light: rgb(0xAE, 0xAE, 0xB2))
  /// The selected tab's fill: the system accent, not an app colour.
  static var selectedTabTint: Color { Color.accentColor.opacity(0.16) }

  // MARK: Colour helpers

  /// A colour that resolves per appearance, so the window reads correctly in
  /// both themes without two asset entries.
  private static func dynamic(dark: NSColor, light: NSColor) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
      })
  }

  private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
  }
}

// MARK: - Page

/// One tab's content: a scrolling column of cards over the page background.
/// Scrolling lives inside the page so switching tabs never resizes the window.
struct SettingsPage<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: SettingsChrome.cardSpacing) {
        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(SettingsChrome.pagePadding)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(SettingsChrome.background)
  }
}

// MARK: - Card

/// A rounded, bordered container holding one or more rows. Rows are separated
/// by `SettingsRowDivider`, placed explicitly by the caller — SwiftUI has no
/// public way to inject a separator between an opaque `ViewBuilder`'s children,
/// and an implicit "every row draws its own top hairline" rule would put one
/// above the first row too.
struct SettingsCard<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 0) {
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(SettingsChrome.surface)
    .clipShape(RoundedRectangle(cornerRadius: SettingsChrome.cardRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: SettingsChrome.cardRadius, style: .continuous)
        .strokeBorder(SettingsChrome.border, lineWidth: 1)
    )
  }
}

/// A card with an optional note under it.
///
/// The note is the sentence that explains a whole group rather than one row.
/// Putting it on the first row's caption instead would read as a remark about
/// that row.
struct SettingsSection<Content: View>: View {
  var footer: String?
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      SettingsCard { content }
      if let footer {
        Text(footer)
          .font(SettingsChrome.rowCaptionFont)
          .foregroundStyle(SettingsChrome.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.leading, 4)
      }
    }
  }
}

/// The hairline between two rows of a card. Full width, not inset: the rows it
/// separates run edge to edge.
struct SettingsRowDivider: View {
  var body: some View {
    Rectangle()
      .fill(SettingsChrome.border)
      .frame(height: 1)
  }
}

// MARK: - Row

/// One row: an optional leading badge, a title, an optional caption under it,
/// and a trailing control.
struct SettingsRow<Leading: View, Control: View>: View {
  let title: String
  var caption: String?
  @ViewBuilder var leading: Leading
  @ViewBuilder var control: Control

  var body: some View {
    HStack(alignment: .center, spacing: SettingsChrome.rowControlSpacing) {
      leading
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(SettingsChrome.rowTitleFont)
          .foregroundStyle(SettingsChrome.primaryText)
        if let caption {
          Text(caption)
            .font(SettingsChrome.rowCaptionFont)
            .foregroundStyle(SettingsChrome.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      control
    }
    .padding(.horizontal, SettingsChrome.rowHorizontalPadding)
    .padding(.vertical, SettingsChrome.rowVerticalPadding)
  }
}

extension SettingsRow where Leading == EmptyView {
  init(title: String, caption: String? = nil, @ViewBuilder control: () -> Control) {
    self.init(title: title, caption: caption, leading: { EmptyView() }, control: control)
  }
}

/// The column titles above a grid of fields. Indented past the label column so
/// each title sits over its own column.
struct SettingsGridHeader: View {
  let titles: [String]

  var body: some View {
    HStack(spacing: SettingsChrome.gridColumnSpacing) {
      Color.clear
        .frame(width: SettingsChrome.gridLabelWidth, height: 1)
      ForEach(titles, id: \.self) { title in
        Text(title)
          .font(SettingsChrome.rowCaptionFont)
          .foregroundStyle(SettingsChrome.tertiaryText)
          .frame(width: SettingsChrome.gridColumnWidth)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, SettingsChrome.rowHorizontalPadding)
    .padding(.top, 10)
  }
}

/// A row whose label sits in a column of its own so the fields beside it line
/// up with the row above. `SettingsRow` cannot do this: its label is greedy, so
/// every row would size its own control differently.
struct SettingsGridRow<Content: View>: View {
  let title: String
  var caption: String?
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: SettingsChrome.gridColumnSpacing) {
        Text(title)
          .font(SettingsChrome.rowTitleFont)
          .foregroundStyle(SettingsChrome.primaryText)
          .frame(width: SettingsChrome.gridLabelWidth, alignment: .leading)
        content
        Spacer(minLength: 0)
      }
      if let caption {
        Text(caption)
          .font(SettingsChrome.rowCaptionFont)
          .foregroundStyle(SettingsChrome.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.horizontal, SettingsChrome.rowHorizontalPadding)
    .padding(.vertical, 10)
  }
}

// MARK: - Tab bar

/// The header strip: icon-over-label tabs on the same surface colour as the
/// title bar. The window draws its content under a transparent title bar, so
/// the strip's top padding is what keeps the tabs clear of the traffic lights.
struct SettingsTabBar<Tab: Hashable>: View {
  let tabs: [Tab]
  let title: (Tab) -> String
  /// SF Symbol name.
  let symbol: (Tab) -> String
  @Binding var selection: Tab

  var body: some View {
    HStack(spacing: SettingsChrome.tabSpacing) {
      ForEach(tabs, id: \.self) { tab($0) }
    }
    .frame(maxWidth: .infinity)
    .padding(.top, SettingsChrome.titleBarHeight + 10)
    .padding(.bottom, 10)
    // The strip reads as one band with the title bar, so it drags the window
    // like one. Scoped to the strip rather than `isMovableByWindowBackground`,
    // which would also move the window when a drag starts on a card.
    .background {
      WindowDragHandle()
        .background(SettingsChrome.surface)
    }
    .overlay(alignment: .bottom) { SettingsRowDivider() }
  }

  private func tab(_ tab: Tab) -> some View {
    let isSelected = tab == selection
    return Button {
      selection = tab
    } label: {
      VStack(spacing: 4) {
        Image(systemName: symbol(tab))
          .font(.system(size: 18, weight: .light))
        Text(title(tab))
          .font(SettingsChrome.tabLabelFont)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
      }
      .frame(width: SettingsChrome.tabSize.width, height: SettingsChrome.tabSize.height)
      .foregroundStyle(isSelected ? Color.accentColor : SettingsChrome.secondaryText)
      .background(
        RoundedRectangle(cornerRadius: SettingsChrome.tabRadius, style: .continuous)
          .fill(isSelected ? SettingsChrome.selectedTabTint : Color.clear)
      )
      .contentShape(RoundedRectangle(cornerRadius: SettingsChrome.tabRadius, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title(tab))
    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
  }
}

/// An invisible AppKit view that starts a window drag on mouse-down, so the
/// SwiftUI view it backs can be grabbed like a title bar. SwiftUI hit-tests it
/// under the foreground content, so the tabs drawn on top keep their clicks.
struct WindowDragHandle: NSViewRepresentable {
  func makeNSView(context: Context) -> DragView { DragView() }

  func updateNSView(_ nsView: DragView, context: Context) {}

  final class DragView: NSView {
    override func mouseDown(with event: NSEvent) {
      window?.performDrag(with: event)
    }
  }
}

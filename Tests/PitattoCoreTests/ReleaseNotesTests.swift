// ReleaseNotesTests.swift
// Verifies that a GitHub release body is split into the blocks the update
// window draws, and that nothing the author wrote as markup reaches the reader
// as markup — the reason the parse exists at all.

import Testing

@testable import PitattoCore

@Suite("Release notes")
struct ReleaseNotesTests {

  // MARK: - Headings

  @Test("Hashes become a heading, and carry their level")
  func readsHeadingLevels() {
    #expect(
      ReleaseNotes.parse("# One\n## Two\n### Three") == [
        .heading(level: 1, text: "One"),
        .heading(level: 2, text: "Two"),
        .heading(level: 3, text: "Three"),
      ])
  }

  @Test("Hashes with no space after them are prose, not a heading")
  func requiresASpaceAfterTheHashes() {
    #expect(ReleaseNotes.parse("#hashtag") == [.paragraph("#hashtag")])
  }

  // MARK: - Lists

  @Test("Every bullet marker starts a list item")
  func readsBulletMarkers() {
    #expect(
      ReleaseNotes.parse("- a\n* b\n+ c\n• d") == [
        .listItem(indent: 0, marker: .bullet, text: "a"),
        .listItem(indent: 0, marker: .bullet, text: "b"),
        .listItem(indent: 0, marker: .bullet, text: "c"),
        .listItem(indent: 0, marker: .bullet, text: "d"),
      ])
  }

  @Test("Nesting is half the leading spaces, and stops at three")
  func readsNestingDepth() {
    #expect(
      ReleaseNotes.parse("- top\n  - one\n    - two\n      - three\n        - deeper") == [
        .listItem(indent: 0, marker: .bullet, text: "top"),
        .listItem(indent: 1, marker: .bullet, text: "one"),
        .listItem(indent: 2, marker: .bullet, text: "two"),
        .listItem(indent: 3, marker: .bullet, text: "three"),
        .listItem(indent: 3, marker: .bullet, text: "deeper"),
      ])
  }

  @Test("A numbered item keeps the number the author wrote")
  func keepsOrderedNumbers() {
    #expect(
      ReleaseNotes.parse("1. first\n2. second\n10. tenth") == [
        .listItem(indent: 0, marker: .ordered(1), text: "first"),
        .listItem(indent: 0, marker: .ordered(2), text: "second"),
        .listItem(indent: 0, marker: .ordered(10), text: "tenth"),
      ])
  }

  // MARK: - Quotes

  @Test("Consecutive quoted lines are one block")
  func groupsQuotedLines() {
    #expect(
      ReleaseNotes.parse("> line one\n> line two\n\nafter") == [
        .quote(["line one", "line two"]),
        .blank,
        .paragraph("after"),
      ])
  }

  @Test("A bare > keeps its blank line inside the quote")
  func keepsBlankQuoteLines() {
    #expect(ReleaseNotes.parse("> first\n>\n> third") == [.quote(["first", "", "third"])])
  }

  // MARK: - Code

  @Test("A fenced block is taken verbatim, markup and all")
  func keepsCodeVerbatim() {
    #expect(
      ReleaseNotes.parse("```\n# not a heading\n**not bold**\n```")
        == [.code("# not a heading\n**not bold**")])
  }

  @Test("A fence nobody closed runs to the end")
  func closesAnUnterminatedFence() {
    #expect(ReleaseNotes.parse("```\nline one\nline two") == [.code("line one\nline two")])
  }

  // MARK: - Tables

  @Test("A table keeps its header, alignments and rows")
  func readsATable() {
    let markdown = """
      | A | B |
      |---|---|
      | 1 | 2 |
      | 3 | 4 |
      """
    #expect(
      ReleaseNotes.parse(markdown) == [
        .table(
          ReleaseNoteTable(
            header: ["A", "B"],
            alignments: [.leading, .leading],
            rows: [["1", "2"], ["3", "4"]]))
      ])
  }

  @Test("The colons in the delimiter row set each column's alignment")
  func readsColumnAlignments() {
    let markdown = """
      | A | B | C |
      |:---|:---:|---:|
      | a | b | c |
      """
    guard case .table(let table) = ReleaseNotes.parse(markdown).first else {
      Issue.record("expected one table")
      return
    }
    #expect(table.alignments == [.leading, .center, .trailing])
  }

  @Test("A row with the wrong number of cells is padded or cut to the header")
  func fitsRowsToTheHeader() {
    let markdown = """
      | A | B | C |
      |---|---|---|
      | short |
      | too | many | cells | here |
      """
    guard case .table(let table) = ReleaseNotes.parse(markdown).first else {
      Issue.record("expected one table")
      return
    }
    #expect(table.rows == [["short", "", ""], ["too", "many", "cells"]])
  }

  @Test("A delimiter row belongs to its table, not to a horizontal rule")
  func doesNotReadADelimiterAsARule() {
    let blocks = ReleaseNotes.parse("| A |\n|---|\n| 1 |")
    #expect(blocks.count == 1)
    guard case .table = blocks.first else {
      Issue.record("expected the delimiter row to be part of the table")
      return
    }
  }

  @Test("Prose with a pipe in it above a rule is still prose")
  func doesNotReadProseAsATable() {
    #expect(
      ReleaseNotes.parse("a | b in prose\n---\nafter") == [
        .paragraph("a | b in prose"),
        .rule,
        .paragraph("after"),
      ])
  }

  // MARK: - Rules

  @Test("Three or more of the same mark on one line is a rule")
  func readsHorizontalRules() {
    #expect(ReleaseNotes.parse("---\n***\n___") == [.rule, .rule, .rule])
  }

  // MARK: - A whole body

  @Test("A release body in the shape the notes are written in leaves no markup behind")
  func readsARealisticReleaseBody() {
    let body = """
      macOS の前面ウィンドウを、ショートカット 1 つで**最大化したり画面の端に寄せたり**するメニューバー常駐アプリケーション。

      ## 主な機能

      - 同じキーを続けて押すと、大きさが 1/2 → 1/4 → 3/4 と変わる
      - 最大化は 全体 → 余白 大 → 余白 小 と変わり、画面の中央で四辺に余白を空ける

      | 項目 | 値 |
      |---|---|
      | 動作要件 | macOS 14 以降 |
      | ライセンス | GPL-3.0 |

      > **注意**: ウィンドウを動かすにはアクセシビリティの許可が必要になる。
      > メニューの「アクセシビリティを許可…」からシステム設定を開く。
      """

    let blocks = ReleaseNotes.parse(body)

    #expect(blocks.contains(.heading(level: 2, text: "主な機能")))
    #expect(blocks.contains { if case .table = $0 { return true } else { return false } })
    #expect(blocks.contains { if case .quote = $0 { return true } else { return false } })

    // The point of the parse: a reader never sees "##", "-", "|" or ">".
    for case .paragraph(let text) in blocks {
      #expect(!text.hasPrefix("#"))
      #expect(!text.hasPrefix("-"))
      #expect(!text.hasPrefix("|"))
      #expect(!text.hasPrefix(">"))
    }
  }
}

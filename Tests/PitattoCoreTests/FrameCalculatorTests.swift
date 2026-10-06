// FrameCalculatorTests.swift
// Verifies where a snapped window lands: the edge fractions, the whole work
// area and its centred margins, the re-seat that keeps a minimum-width window
// against its edge, and the AppKit ↔ Accessibility coordinate flip.

import CoreGraphics
import Testing

@testable import PitattoCore

@Suite("Frame calculator")
struct FrameCalculatorTests {

  /// A 2560×1600 built-in display with the menu bar taken off the top.
  private let workArea = CGRect(x: 0, y: 0, width: 2560, height: 1562)
  /// A second display to the right, at a non-zero origin in AppKit's global space.
  private let secondary = CGRect(x: 2560, y: 200, width: 1920, height: 1055)

  /// The three edge steps and the height each gives on `workArea`.
  private static let edgeHeights: [(SnapSize, CGFloat)] = [
    (.oneHalf, 781), (.oneQuarter, 391), (.threeQuarters, 1172),
  ]

  @Test("Maximize takes the whole work area")
  func maximizeTakesTheWholeWorkArea() {
    #expect(FrameCalculator.frame(for: .maximize, size: .whole, in: workArea) == workArea)
  }

  @Test(
    "A margin leaves the same gap on all four sides, whatever the shape of the display",
    arguments: [(SnapSize.smallMargin, 24), (.largeMargin, 64)] as [(SnapSize, CGFloat)])
  func maximizeMarginsLeaveTheSameGapOnEverySide(_ size: SnapSize, _ points: CGFloat) {
    let frame = FrameCalculator.frame(for: .maximize, size: size, in: secondary)
    #expect(frame == secondary.insetBy(dx: points, dy: points))
  }

  @Test("A maximize window that refused to shrink is centred again at the size it took")
  func reseatCentresAMaximizeWindowThatRefusedToShrink() {
    let area = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let measured = CGRect(x: 90, y: 55, width: 1300, height: 800)
    let seated = FrameCalculator.reseat(measured, for: .maximize, in: area)
    #expect(seated == CGRect(x: 70, y: 38, width: 1300, height: 800))
  }

  @Test("A maximize window larger than the area hangs from the top-left, title bar on screen")
  func reseatHangsAMaximizeWindowLargerThanTheAreaFromTheTopLeft() {
    let area = CGRect(x: 0, y: 100, width: 800, height: 600)
    let measured = CGRect(x: 0, y: 0, width: 900, height: 700)
    let seated = FrameCalculator.reseat(measured, for: .maximize, in: area)
    #expect(seated.minX == area.minX)
    #expect(seated.maxY == area.maxY)
  }

  @Test(
    "A right snap touches the right edge at every step",
    arguments: [(SnapSize.oneHalf, 1280), (.oneQuarter, 640), (.threeQuarters, 1920)]
      as [(SnapSize, CGFloat)])
  func rightSnapTouchesTheRightEdgeAtEveryStep(_ size: SnapSize, _ width: CGFloat) {
    let frame = FrameCalculator.frame(for: .right, size: size, in: workArea)
    #expect(frame.width == width)
    #expect(frame.maxX == workArea.maxX)
    #expect(frame.height == workArea.height)
  }

  @Test("A top snap touches the top edge and spans the width", arguments: edgeHeights)
  func topSnapTouchesTheTopEdgeAtEveryStep(_ size: SnapSize, _ height: CGFloat) {
    let frame = FrameCalculator.frame(for: .top, size: size, in: workArea)
    #expect(frame.height == height)
    #expect(frame.maxY == workArea.maxY)
    #expect(frame.width == workArea.width)
    #expect(frame.minX == workArea.minX)
  }

  @Test("A bottom snap touches the bottom edge and spans the width", arguments: edgeHeights)
  func bottomSnapTouchesTheBottomEdgeAtEveryStep(_ size: SnapSize, _ height: CGFloat) {
    let frame = FrameCalculator.frame(for: .bottom, size: size, in: workArea)
    #expect(frame.height == height)
    #expect(frame.minY == workArea.minY)
    #expect(frame.width == workArea.width)
  }

  @Test("A bottom snap lands on the given display's bottom, not the primary's")
  func bottomSnapUsesTheGivenWorkAreaOrigin() {
    let frame = FrameCalculator.frame(for: .bottom, size: .oneHalf, in: secondary)
    #expect(frame.minY == 200)
    #expect(frame.minX == 2560)
    #expect(frame.height == 528)
  }

  @Test("A left snap touches the left edge")
  func leftSnapTouchesTheLeftEdge() {
    let frame = FrameCalculator.frame(for: .left, size: .oneQuarter, in: workArea)
    #expect(frame.minX == workArea.minX)
    #expect(frame.width == 640)
    #expect(frame.height == workArea.height)
  }

  @Test("A right snap touches the given display's edge, not the primary's")
  func snapUsesTheGivenWorkAreaOrigin() {
    let frame = FrameCalculator.frame(for: .right, size: .oneHalf, in: secondary)
    #expect(frame.maxX == 4480)
    #expect(frame.minY == 200)
    #expect(frame.width == 960)
  }

  @Test("A width that does not divide evenly still gives whole points")
  func fractionalWidthsAreRounded() {
    let odd = CGRect(x: 0, y: 0, width: 1707, height: 1000)
    let frame = FrameCalculator.frame(for: .right, size: .oneQuarter, in: odd)
    #expect(frame.width == 427)
    #expect(frame.width.truncatingRemainder(dividingBy: 1) == 0)
  }

  /// A scaled display can report a work area on a half point. The next press
  /// compares frames for equality, so every component has to be rounded before
  /// the arithmetic, not only the width it produces.
  @Test("A work area on a half point is rounded before anything is measured from it")
  func fractionalWorkAreaIsRoundedFirst() {
    let scaled = CGRect(x: 0, y: 0, width: 1512.5, height: 944.5)
    let frame = FrameCalculator.frame(for: .right, size: .oneHalf, in: scaled)
    for component in [frame.minX, frame.minY, frame.width, frame.height] {
      #expect(component.truncatingRemainder(dividingBy: 1) == 0, "\(frame)")
    }
    #expect(frame.maxX == 1513)

    let measured = CGRect(x: 700, y: 0, width: 800, height: 945)
    let seated = FrameCalculator.reseat(measured, for: .right, in: scaled)
    #expect(seated.minX == 713)
    #expect(seated.maxX == 1513)
  }

  @Test("An oversize window is pushed back against the right edge at the width it kept")
  func reseatPushesAnOversizeWindowBackAgainstTheRightEdge() {
    // Terminal refuses to go below about 240pt, so a quarter snap on a narrow
    // work area comes back wider than asked and overhangs the screen.
    let area = CGRect(x: 0, y: 0, width: 800, height: 600)
    let measured = CGRect(x: 640, y: 0, width: 240, height: 600)
    let seated = FrameCalculator.reseat(measured, for: .right, in: area)
    #expect(seated.maxX == area.maxX)
    #expect(seated.width == 240, "the size the window insisted on is kept")
  }

  /// The one action that sits on the bottom edge. A window that would not go
  /// as short as a bottom snap asked for is pushed down, not left hanging from
  /// the top with a gap under it.
  @Test("A short bottom-snap window sits on the bottom edge")
  func reseatSitsAShortBottomWindowOnTheBottomEdge() {
    let area = CGRect(x: 0, y: 100, width: 1440, height: 875)
    let measured = CGRect(x: 0, y: 500, width: 1440, height: 400)
    let seated = FrameCalculator.reseat(measured, for: .bottom, in: area)
    #expect(seated.minY == area.minY)
    #expect(seated.minX == area.minX)
    #expect(seated.height == 400, "the size the window insisted on is kept")
  }

  @Test("A short top-snap window keeps the top hang the horizontal snaps have")
  func reseatHangsAShortTopWindowFromTheTop() {
    let area = CGRect(x: 0, y: 100, width: 1440, height: 875)
    let measured = CGRect(x: 0, y: 100, width: 1440, height: 400)
    let seated = FrameCalculator.reseat(measured, for: .top, in: area)
    #expect(seated.maxY == area.maxY)
  }

  @Test("A short left-snap window hangs from the top of the work area")
  func reseatKeepsAShortWindowHangingFromTheTop() {
    let area = CGRect(x: 0, y: 100, width: 800, height: 600)
    let measured = CGRect(x: 0, y: 100, width: 400, height: 300)
    let seated = FrameCalculator.reseat(measured, for: .left, in: area)
    #expect(seated.maxY == area.maxY)
    #expect(seated.minX == area.minX)
  }

  @Test("The screen a window overlaps most is the one it is on")
  func theScreenWithTheMostOverlapWins() {
    let screens = [CGRect(x: 0, y: 0, width: 2560, height: 1600), secondary]
    let mostlyPrimary = CGRect(x: 2000, y: 300, width: 1000, height: 500)
    let mostlySecondary = CGRect(x: 2200, y: 300, width: 1000, height: 500)
    #expect(FrameCalculator.indexOfScreen(mostOverlapping: mostlyPrimary, in: screens) == 0)
    #expect(FrameCalculator.indexOfScreen(mostOverlapping: mostlySecondary, in: screens) == 1)
  }

  @Test("A window split evenly between two screens goes to the earlier one")
  func anEvenSplitGoesToTheEarlierScreen() {
    let screens = [
      CGRect(x: 0, y: 0, width: 1000, height: 1000),
      CGRect(x: 1000, y: 0, width: 1000, height: 1000),
    ]
    let split = CGRect(x: 500, y: 0, width: 1000, height: 1000)
    #expect(FrameCalculator.indexOfScreen(mostOverlapping: split, in: screens) == 0)
  }

  @Test("A window off every screen is on none of them")
  func aWindowOffEveryScreenIsOnNone() {
    let screens = [workArea, secondary]
    let offscreen = CGRect(x: 9000, y: 9000, width: 100, height: 100)
    #expect(FrameCalculator.indexOfScreen(mostOverlapping: offscreen, in: screens) == nil)
    #expect(FrameCalculator.indexOfScreen(mostOverlapping: offscreen, in: []) == nil)
  }

  @Test("The coordinate flip round-trips")
  func coordinateFlipRoundTrips() {
    let primaryHeight: CGFloat = 1600
    let frame = CGRect(x: 1280, y: 38, width: 1280, height: 1562)

    let origin = FrameCalculator.axOrigin(of: frame, primaryScreenHeight: primaryHeight)
    #expect(origin == CGPoint(x: 1280, y: 0), "a full-height window starts at the top in AX")

    let back = FrameCalculator.appKitFrame(
      axOrigin: origin, size: frame.size, primaryScreenHeight: primaryHeight)
    #expect(back == frame)
  }

  /// A window on a display below the primary one has a negative AppKit y, and
  /// a y past the primary's height in Accessibility coordinates.
  @Test("The coordinate flip handles a display below the primary")
  func coordinateFlipHandlesADisplayBelowThePrimary() {
    let primaryHeight: CGFloat = 1600
    let frame = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
    let origin = FrameCalculator.axOrigin(of: frame, primaryScreenHeight: primaryHeight)
    #expect(origin == CGPoint(x: 0, y: 1600))
    #expect(
      FrameCalculator.appKitFrame(
        axOrigin: origin, size: frame.size, primaryScreenHeight: primaryHeight) == frame)
  }
}

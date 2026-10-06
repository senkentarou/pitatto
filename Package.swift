// swift-tools-version: 6.0
import PackageDescription

// PitattoCore holds every decision the app makes and imports nothing beyond
// Foundation and CoreGraphics; Pitatto holds every OS call. The split is what
// lets `swift test` cover the frame arithmetic and the repeat-press judgement
// without an Accessibility grant, a hot key, or a connected display.
let package = Package(
  name: "Pitatto",
  platforms: [.macOS(.v14)],
  targets: [
    .target(
      name: "PitattoCore",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .executableTarget(
      name: "Pitatto",
      dependencies: ["PitattoCore"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "PitattoCoreTests",
      dependencies: ["PitattoCore"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
  ]
)

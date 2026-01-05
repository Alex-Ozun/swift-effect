// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
  name: "swift-effect",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
    .tvOS(.v18),
    .visionOS(.v2),
    .watchOS(.v11),
  ],
  products: [
    .library(
      name: "Effect",
      targets: ["Effect"],
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "602.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-macro-testing.git", exact: "0.6.4"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.8.0"),
    .package(url: "https://github.com/groue/Semaphore", exact: "0.1.0"),
  ],
  targets: [
    .testTarget(
      name: "EffectMacrosTests",
      dependencies: [
        "Effect",
        "EffectMacros",
        .product(name: "MacroTesting", package: "swift-macro-testing"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
      ],
      path: "Tests/EffectMacrosTests",
    ),
    .testTarget(
      name: "EffectTests",
      dependencies: [
        "Effect",
      ],
      path: "Tests/EffectTests",
      swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")],
    ),
    .target(
      name: "Effect",
      dependencies: [
        "EffectMacros",
        .product(name: "Semaphore", package: "Semaphore"),
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
      ],
      path: "Sources/Effect",
      swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")],
    ),
    .macro(
      name: "EffectMacros",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
      ],
      path: "Sources/EffectMacros",
    ),
  ],
  swiftLanguageModes: [.v6],
)

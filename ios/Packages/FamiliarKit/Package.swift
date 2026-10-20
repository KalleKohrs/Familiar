// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FamiliarKit",
    defaultLocalization: "de",
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "FamiliarCore", targets: ["FamiliarCore"]),
        .library(name: "FamiliarDesign", targets: ["FamiliarDesign"]),
        .library(name: "FamiliarActivity", targets: ["FamiliarActivity"]),
    ],
    targets: [
        // Domänenlogik ohne UI-Abhängigkeiten.
        .target(name: "FamiliarCore"),
        // Design-Tokens und wiederverwendbare SwiftUI-Komponenten.
        .target(name: "FamiliarDesign", dependencies: ["FamiliarCore"]),
        // Live-Activity-Attribute, gemeinsam für App und Widget-Extension.
        .target(name: "FamiliarActivity", dependencies: ["FamiliarCore"]),
        .testTarget(name: "FamiliarCoreTests", dependencies: ["FamiliarCore"]),
        .testTarget(name: "FamiliarActivityTests", dependencies: ["FamiliarActivity"]),
    ]
)

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
        .library(name: "FamiliarData", targets: ["FamiliarData"]),
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.55.4"),
    ],
    targets: [
        // Domänenlogik ohne UI-Abhängigkeiten.
        .target(name: "FamiliarCore"),
        // Design-Tokens und wiederverwendbare SwiftUI-Komponenten.
        .target(name: "FamiliarDesign", dependencies: ["FamiliarCore"]),
        // Live-Activity-Attribute, gemeinsam für App und Widget-Extension.
        .target(name: "FamiliarActivity", dependencies: ["FamiliarCore"]),
        // Datenzugriff über Supabase (Auth, Datenbank, Storage). Nur für die App, nicht für die Extension.
        .target(
            name: "FamiliarData",
            dependencies: ["FamiliarCore", .product(name: "Supabase", package: "supabase-swift")]
        ),
        .testTarget(name: "FamiliarCoreTests", dependencies: ["FamiliarCore"]),
        .testTarget(name: "FamiliarActivityTests", dependencies: ["FamiliarActivity"]),
        .testTarget(name: "FamiliarDataTests", dependencies: ["FamiliarData"]),
    ]
)

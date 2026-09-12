// swift-tools-version: 6.2
// legibility:description: Bidirectional translation layer between BusinessMath computational models and Excel workbooks with live formulas.

import PackageDescription

let package = Package(
    name: "BusinessMathExcel",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "BusinessMathExcel", targets: ["BusinessMathExcel"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpurnell/BusinessMath", .upToNextMinor(from: "3.0.0-alpha.4")),
        // `upToNextMinor` rather than `exact:` or `from:`. The family ships breaking
        // changes in minor versions while pre-1.0, so a patch flows freely and a minor
        // stays a deliberate bump. `exact:` deadlocked resolution whenever a shared
        // dependency moved ahead of one consumer.
        .package(url: "https://github.com/jpurnell/SwiftXLSX", .upToNextMinor(from: "0.25.0")),
        .package(url: "https://github.com/jpurnell/SwiftExcelFunctions", .upToNextMinor(from: "0.9.3")),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3"),
    ],
    targets: [
        .target(
            name: "BusinessMathExcel",
            dependencies: [
                .product(name: "SwiftXLSX", package: "SwiftXLSX"),
                .product(name: "BusinessMath", package: "BusinessMath"),
                .product(name: "SwiftExcelFunctions", package: "SwiftExcelFunctions"),
            ],
            path: "Sources/BusinessMathExcel",
            // The catalogue stays part of the target so the DocC plugin still finds it via
            // `sourceFiles`; declaring it keeps SwiftPM's native build system from calling it
            // an unhandled file. `exclude:` would silence that warning by hiding the catalogue
            // from DocC entirely, which lints nothing.
            resources: [.copy("BusinessMathExcel.docc")]
        ),
        .testTarget(
            name: "BusinessMathExcelTests",
            dependencies: ["BusinessMathExcel"],
            path: "Tests/BusinessMathExcelTests"
        ),
    ]
)

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
        .package(url: "https://github.com/jpurnell/BusinessMath", exact: "2.9.0"),
        .package(url: "https://github.com/jpurnell/SwiftXLSX", exact: "0.21.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3"),
    ],
    targets: [
        .target(
            name: "BusinessMathExcel",
            dependencies: [
                .product(name: "SwiftXLSX", package: "SwiftXLSX"),
                .product(name: "BusinessMath", package: "BusinessMath"),
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

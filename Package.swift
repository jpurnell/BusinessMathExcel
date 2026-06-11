// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "BusinessMathExcel",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "BusinessMathExcel", targets: ["BusinessMathExcel"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpurnell/BusinessMath", exact: "2.2.1"),
        .package(url: "https://github.com/jpurnell/SwiftXLSX", exact: "0.2.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3"),
    ],
    targets: [
        .target(
            name: "BusinessMathExcel",
            dependencies: [
                .product(name: "SwiftXLSX", package: "SwiftXLSX"),
                .product(name: "BusinessMath", package: "BusinessMath"),
            ],
            path: "Sources/BusinessMathExcel"
        ),
        .testTarget(
            name: "BusinessMathExcelTests",
            dependencies: ["BusinessMathExcel"],
            path: "Tests/BusinessMathExcelTests"
        ),
    ]
)

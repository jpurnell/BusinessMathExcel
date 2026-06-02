// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "BusinessMathExcel",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "BusinessMathExcel", targets: ["BusinessMathExcel"]),
    ],
    dependencies: [
        .package(path: "../BusinessMath"),
        .package(path: "../SwiftXLSX"),
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

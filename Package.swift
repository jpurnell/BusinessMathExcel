// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BusinessMathExcel",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "BusinessMathExcel", targets: ["BusinessMathExcel"]),
    ],
    dependencies: [
        .package(path: "../BusinessMath"),
        .package(url: "https://github.com/jpurnell/SwiftXLSX.git", from: "0.1.0"),
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

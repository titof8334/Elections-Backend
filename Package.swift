// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Elections",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.8.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.3.0"),
        .package(url: "https://github.com/vapor/jwt.git", from: "4.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "Run",
            dependencies: [.target(name: "App")],
            path: "Sources/Run"
        ),
        .target(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "JWT", package: "jwt"),
            ],
            path: "Sources/App"
        ),
//        .testTarget(
//            name: "AppTests",
//            dependencies: [
//                .target(name: "App"),
//                .product(name: "XCTVapor", package: "vapor"),
//            ],
//            path: "Tests/AppTests"
//        ),
    ]
)

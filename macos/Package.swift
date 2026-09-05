// swift-tools-version:5.9
import PackageDescription

// Layout
//   DisplayShotKit     – all app code (menu bar app, overlay, tools, export)
//   DisplayShot        – thin executable that launches the kit
//   DisplayShotChecks  – self-contained test runner (`swift run DisplayShotChecks`), so the
//                        tests run with the Command Line Tools alone (no XCTest needed)
let package = Package(
    name: "DisplayShot",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "DisplayShotKit",
            path: "Sources/DisplayShotKit",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("CoreImage"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "DisplayShot",
            dependencies: ["DisplayShotKit"],
            path: "Sources/DisplayShot"
        ),
        .executableTarget(
            name: "DisplayShotChecks",
            dependencies: ["DisplayShotKit"],
            path: "Sources/DisplayShotChecks"
        ),
    ]
)

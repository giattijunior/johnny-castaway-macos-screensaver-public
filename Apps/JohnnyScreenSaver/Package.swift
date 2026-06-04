// swift-tools-version: 6.0
//
// JohnnyScreenSaver — the screensaver bundle target.
//
// SwiftPM can't natively produce either a `.saver` bundle (legacy
// CFBundle plugin loaded by `legacyScreenSaver`) or a `.appex` bundle
// (Tahoe-era ExtensionKit plugin loaded by the screen-saver host).
// We work around this by producing a *dynamic library* here, then
// wrapping it in either bundle structure via the build script:
//
//   • Scripts/build-saver.sh   → legacy .saver (CFBundlePackageType=BNDL)
//   • Scripts/build-appex.sh   → Tahoe .appex (CFBundlePackageType=XPC!)
//
// The dylib's Mach-O `MH_BUNDLE` type is achieved by passing the
// `-bundle` linker flag (see linkerSettings.unsafeFlags below) so the
// loader treats it correctly when CFBundle dlopen()s it. The same
// dylib serves both host pipelines — the legacy `JohnnyScreenSaverView`
// (NSPrincipalClass) and the Tahoe `JohnnyScreensaverExtension` +
// `JohnnyScreensaverViewController` (NSExtensionPrincipalClass +
// ScreenSaverViewControllerClass) all live in the same binary.
//
// Building (legacy .saver):
//   $ Scripts/build-saver.sh
//
// Building (Tahoe .appex):
//   $ Scripts/build-appex.sh
//   $ Scripts/build-appex.sh --install      (copies to
//       ~/Library/Application Support/ExtensionKit/Extensions/)

import PackageDescription

let packageDir: String = {
    let fp     = String(describing: #filePath)
    let suffix = "/Package.swift"
    return fp.hasSuffix(suffix) ? String(fp.dropLast(suffix.count)) : fp
}()

let package = Package(
    name: "JohnnyScreenSaver",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "JohnnyScreenSaver",
            type: .dynamic,
            targets: ["JohnnyScreenSaver"]
        ),
    ],
    dependencies: [
        .package(path: "../../Packages/JohnnyResources"),
        .package(path: "../../Packages/JohnnyEngine"),
        .package(path: "../../Packages/JohnnyMetalRenderer"),
        .package(path: "../../Packages/JohnnyDebug"),
    ],
    targets: [
        .target(
            name: "JohnnyScreenSaver",
            dependencies: [
                .product(name: "JohnnyResources",     package: "JohnnyResources"),
                .product(name: "JohnnyEngine",        package: "JohnnyEngine"),
                .product(name: "JohnnyMetalRenderer", package: "JohnnyMetalRenderer"),
                .product(name: "JohnnyDebug",         package: "JohnnyDebug"),
            ],
            path: "Sources/JohnnyScreenSaver",
            linkerSettings: [
                // Produce a Mach-O MH_BUNDLE (the format CFBundle and
                // ExtensionKit both expect when dlopen()-ing a plugin).
                // Without this, SwiftPM emits a regular dylib which
                // neither host will load as a screensaver plugin.
                //
                // `-undefined dynamic_lookup` lets us reference
                // Objective-C classes (ScreenSaverView, NSPrincipalClass,
                // etc.) that are provided by the host process at load
                // time, without forcing the linker to resolve them at
                // build time.
                .unsafeFlags([
                    "-Xlinker", "-bundle",
                    "-Xlinker", "-undefined",
                    "-Xlinker", "dynamic_lookup",
                ]),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

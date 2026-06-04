#!/bin/bash
# build-appex.sh
#
# Build the JohnnyScreenSaver.appex bundle for macOS 26 Tahoe.
#
# This is the Tahoe-era counterpart to build-saver.sh. Both build
# scripts produce a bundle around the same dylib (libJohnnyScreenSaver.dylib
# built by `swift build -c release`); they differ only in the wrapper:
#
#   build-saver.sh  →  JohnnyScreenSaver.saver       (CFBundlePackageType=BNDL)
#                        legacy .saver for systems that still go
#                        through legacyScreenSaver (Sonoma/Sequoia).
#                        Installed to ~/Library/Screen Savers/.
#
#   build-appex.sh  →  JohnnyScreenSaver.appex       (CFBundlePackageType=XPC!)
#                        native ExtensionKit plugin for macOS 26
#                        Tahoe. The Tahoe screen-saver host
#                        loads the .appex via NSExtension; this is
#                        the path that fixes the -10811 LaunchServices
#                        bug that prevents legacy .saver bundles in
#                        ~/Library/Screen Savers/ from being indexed
#                        on Tahoe. Installed to
#                        ~/Library/Application Support/ExtensionKit/Extensions/.
#
# Steps:
#   1. swift build -c release  (produces libJohnnyScreenSaver.dylib)
#   2. Assemble JohnnyScreenSaver.appex/Contents/{MacOS,Resources}/
#   3. Copy the binary, Info-appex.plist → Info.plist, version.plist,
#      metallib (if any)
#   4. Ad-hoc codesign the bundle
#
# Flags:
#   --debug     Build configuration debug (default: release)
#   --install   Copy to ~/Library/Application Support/ExtensionKit/Extensions/
#               after building (Tahoe's native path for user-installed
#               screensaver extensions).
#   --reload    With --install, kill the running screensaver processes
#               so System Settings re-loads the bundle fresh on next
#               preview/activation.
#
# Output: ./build/JohnnyScreenSaver.appex

set -euo pipefail

CONFIG="release"
INSTALL=0
RELOAD=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)   CONFIG="debug";   shift ;;
        --install) INSTALL=1;        shift ;;
        --reload)  RELOAD=1;         shift ;;
        *) echo "unknown flag: $1" >&2; exit 1 ;;
    esac
done

# Resolve script-dir-relative paths so the script works from any CWD.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"     # Apps/JohnnyScreenSaver
BUILD_DIR="$PKG_DIR/build"
APPEX_NAME="JohnnyScreenSaver"
APPEX_BUNDLE="$BUILD_DIR/$APPEX_NAME.appex"

echo "==> Building $APPEX_NAME ($CONFIG) for Tahoe/.appex…"
cd "$PKG_DIR"
swift build -c "$CONFIG"

DYLIB="$PKG_DIR/.build/$CONFIG/lib${APPEX_NAME}.dylib"
if [[ ! -f "$DYLIB" ]]; then
    echo "Build failed: $DYLIB not found" >&2
    exit 1
fi

echo "==> Assembling .appex bundle…"
rm -rf "$APPEX_BUNDLE"
mkdir -p "$APPEX_BUNDLE/Contents/MacOS"
mkdir -p "$APPEX_BUNDLE/Contents/Resources"

# The Mach-O executable, named to match CFBundleExecutable in Info.plist.
cp "$DYLIB" "$APPEX_BUNDLE/Contents/MacOS/$APPEX_NAME"
chmod +x "$APPEX_BUNDLE/Contents/MacOS/$APPEX_NAME"

# Info.plist — use the Tahoe-specific one (CFBundlePackageType=XPC!
# + NSExtension block + ScreenSaverViewControllerClass). The legacy
# Info.plist lives at the same path but is used by build-saver.sh.
cp "$PKG_DIR/Resources/Info-appex.plist" "$APPEX_BUNDLE/Contents/Info.plist"

# version.plist — required by ExtensionKit in addition to Info.plist.
cp "$PKG_DIR/Resources/version.plist" "$APPEX_BUNDLE/Contents/version.plist"

# Renderer's compiled Metal library, if present.
METALLIB_CANDIDATES=(
    "$PKG_DIR/.build/$CONFIG/JohnnyMetalRenderer_JohnnyMetalRenderer.bundle/Contents/Resources/default.metallib"
    "$PKG_DIR/.build/$CONFIG/JohnnyMetalRenderer_JohnnyMetalRenderer.bundle/default.metallib"
)
for cand in "${METALLIB_CANDIDATES[@]}"; do
    if [[ -f "$cand" ]]; then
        cp "$cand" "$APPEX_BUNDLE/Contents/Resources/"
        echo "    metallib: $cand"
        break
    fi
done

# Sanity: both the legacy principal class and the Tahoe principal
# class must be exported by the dylib. If the symbols are missing
# the bundle will load but the host won't be able to instantiate
# anything, and the system log will show a
# NSClassFromString(<NSExtensionPrincipalClass>) failure.
NMS=$(nm -gU "$APPEX_BUNDLE/Contents/MacOS/$APPEX_NAME" 2>/dev/null || true)
if ! echo "$NMS" | grep -q "_OBJC_CLASS_\$_JohnnyScreensaverExtension"; then
    echo "WARNING: principal class _OBJC_CLASS_\$_JohnnyScreensaverExtension not exported" >&2
    echo "  ExtensionKit host will fail to instantiate the extension." >&2
fi
if ! echo "$NMS" | grep -q "_OBJC_CLASS_\$_JohnnyScreensaverViewController"; then
    echo "WARNING: view controller _OBJC_CLASS_\$_JohnnyScreensaverViewController not exported" >&2
    echo "  ExtensionKit host will fail to instantiate the view controller." >&2
fi
if ! echo "$NMS" | grep -q "_OBJC_CLASS_\$_JohnnyScreenSaverView"; then
    echo "WARNING: legacy view class _OBJC_CLASS_\$_JohnnyScreenSaverView not exported" >&2
    echo "  Preview / configure sheet may not render correctly." >&2
fi

echo "==> Signing bundle (ad-hoc with Tahoe screensaver entitlements)…"
# Strip any Finder metadata / resource forks first — codesign refuses
# to seal a bundle that has them. Then re-sign the whole bundle so
# the identifier becomes nz.petesmith.JohnnyScreenSaver (from
# Info.plist), Info.plist is bound into the CodeDirectory, and
# Sealed Resources are created. Without this step the linker leaves
# only an adhoc,linker-signed stub on the Mach-O, which does NOT
# bind Info.plist — System Settings never matches the bundle to
# its configure-sheet entry.
#
# The entitlements file is REQUIRED on Tahoe. Without
# `com.apple.developer.extension-host.screensaver` the
# ExtensionKit host loads the bundle but refuses to instantiate
# the principal class. Without `com.apple.security.app-sandbox`
# the ExtensionKit host logs "Extension is not entitled to run
# in the App Sandbox" and the bundle is invisible to pluginkit.
# See Resources/JohnnyScreenSaver.appex.entitlements for the
# full entitlement set.
xattr -cr "$APPEX_BUNDLE"
codesign --force --deep --sign - \
    --entitlements "$PKG_DIR/Resources/JohnnyScreenSaver.appex.entitlements" \
    "$APPEX_BUNDLE"
codesign --verify --verbose "$APPEX_BUNDLE"

echo "==> Built: $APPEX_BUNDLE"

if [[ $INSTALL -eq 1 ]]; then
    # Tahoe's native path for user-installed screensaver extensions.
    # ExtensionKit watches this directory for new bundles and indexes
    # them automatically — no `lsregister -f` or
    # `pluginkit -a` required.
    INSTALL_DIR="$HOME/Library/Application Support/ExtensionKit/Extensions"
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALL_DIR/$APPEX_NAME.appex"
    cp -R "$APPEX_BUNDLE" "$INSTALL_DIR/"
    # Strip any xattrs cp -R may have added to the installed copy.
    # The com.apple.provenance attribute (if set by Tahoe's
    # sandbox) does NOT block ExtensionKit indexing the way it
    # blocked legacy LaunchServices — so we don't have to
    # overwrite the bundle through ditto/zip like we did for the
    # .saver path.
    xattr -cr "$INSTALL_DIR/$APPEX_NAME.appex"
    echo "==> Installed: $INSTALL_DIR/$APPEX_NAME.appex"

    if [[ $RELOAD -eq 1 ]]; then
        # Kill the running screensaver processes so System Settings
        # re-loads the extension fresh on next preview/activation.
        killall legacyScreenSaver 2>/dev/null || true
        killall ScreenSaverEngine 2>/dev/null || true
        # The Tahoe ExtensionKit host runs as `wallpaperextensiond`
        # for the desktop wallpaper and `legacyScreenSaver` for
        # screensaver previews. Restarting cfprefsd is also wise
        # to flush any cached preferences that pointed at the old
        # (legacy) bundle id.
        killall cfprefsd 2>/dev/null || true
        echo "==> Killed legacyScreenSaver / ScreenSaverEngine / cfprefsd (will respawn on demand)"
    fi
fi

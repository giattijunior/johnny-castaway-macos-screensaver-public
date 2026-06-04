#!/usr/bin/env bash
# Install.sh — Johnny Castaway screensaver, single-shot installer (BYO)
#
# This is the public-repo build of Install.sh. The pre-built binary
# bundles and the Sierra resource files (RESOURCE.MAP, RESOURCE.001)
# are NOT included here — those are © 1992 Sierra/Dynamix and live
# only in the private backup repo
# (giattijunior/johnny-castaway-macos-screensaver). This script:
#
#   1. Locates the bundles (prefer pre-built in this directory; fall
#      back to building from source via `swift build` if missing).
#   2. Verifies file integrity via SHA256 against
#      Release/manifests/SHA256SUMS if present.
#   3. Copies the resource bundle (RESOURCE.MAP + RESOURCE.001) from
#      the path you pass in (or that you set in RESOURCE_DIR env) to
#      ~/Library/Application Support/Johnny Castaway Resources/.
#   4. Copies the .saver (legacy) to ~/Library/Screen Savers/.
#   5. Copies the .appex (Tahoe/ExtensionKit) to
#      ~/Library/Application Support/ExtensionKit/Extensions/.
#   6. Ad-hoc codesigns the .appex with the bundled entitlements file.
#   7. Writes a settings.json so the screensaver finds the resource
#      folder on first run (no NSOpenPanel required).
#   8. Kills legacyScreenSaver / ScreenSaverEngine / cfprefsd so System
#      Settings picks up the change on the next preview/activation.
#   9. Tells the user where the screensaver is and what to do next.
#
# Idempotent: re-running removes the previous install and reinstalls.
# No sudo required: every install path is under $HOME/Library.
#
# Usage:
#   bash Install.sh                            # install (auto-build)
#   bash Install.sh --resource-dir <path>      # explicit Sierra assets
#   bash Install.sh --build-from-source        # rebuild dylibs first
#   bash Install.sh --uninstall                # remove everything
#   bash Install.sh --verify                   # just check files/integrity
#
# The --resource-dir flag is required if the bundles are not pre-built
# in this directory (i.e. on a fresh public clone, where the asset
# files are not vendored).

set -euo pipefail

# -----------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Bundles the script will install (pre-built path; may not exist in
# the public repo)
SAVER_SRC="$SCRIPT_DIR/../bundles/JohnnyScreenSaver.saver"
APPEX_SRC="$SCRIPT_DIR/../bundles/JohnnyScreenSaver.appex"
ASSETS_SRC="$SCRIPT_DIR/../Johnny Castaway Resources"
ENTITLEMENTS_SRC="$SCRIPT_DIR/../bundles/JohnnyScreenSaver.appex.entitlements"

# Install paths (all under $HOME; no sudo needed)
SAVER_DST="$HOME/Library/Screen Savers/JohnnyScreenSaver.saver"
APPEX_DST="$HOME/Library/Application Support/ExtensionKit/Extensions/JohnnyScreenSaver.appex"
ASSETS_DST="$HOME/Library/Application Support/Johnny Castaway Resources"
SETTINGS_DIR="$HOME/Library/Application Support/nz.petesmith.JohnnyScreenSaver"
SETTINGS_JSON="$SETTINGS_DIR/settings.json"

# Screensaver bundle identifier (must match the Info.plist of both bundles)
SAVER_ID="nz.petesmith.JohnnyScreenSaver"

# Defaults
DO_BUILD_FROM_SOURCE=0
DO_UNINSTALL=0
DO_VERIFY=0
RESOURCE_DIR=""

# -----------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build-from-source) DO_BUILD_FROM_SOURCE=1; shift ;;
        --uninstall)         DO_UNINSTALL=1;         shift ;;
        --verify)            DO_VERIFY=1;            shift ;;
        --resource-dir)      RESOURCE_DIR="$2";      shift 2 ;;
        -h|--help)
            sed -n '3,35p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown flag: $1" >&2; exit 1 ;;
    esac
done

# Also accept RESOURCE_DIR from the environment
if [[ -z "$RESOURCE_DIR" && -n "${RESOURCE_DIR:-}" ]]; then
    RESOURCE_DIR="$RESOURCE_DIR"
fi

# -----------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------

log()  { printf '\033[1;34m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n'    "$*" >&2; }
fail() { printf '\033[1;31m[fail]\033[0m %s\n'    "$*" >&2; exit 1; }

# Validate a binary's SHA256 against the manifest if present.
# Usage: verify_sha256 <file>
#
# The manifest stores the same path the installer passes to this
# function (resolved relative to Release/scripts/, e.g.
# `Release/scripts/../bundles/JohnnyScreenSaver.saver/...`).  Match is
# by exact path.
verify_sha256() {
    local file="$1"
    local manifest="$SCRIPT_DIR/../manifests/SHA256SUMS"
    [[ -f "$manifest" ]] || { warn "no SHA256SUMS manifest, skipping verification"; return 0; }

    # Strip the leading "Release/scripts/" because shasum was run from
    # the repo root. The install path on disk is "$SCRIPT_DIR/$rest" but
    # the manifest stores "Release/scripts/$rest".
    local rel="${file#$SCRIPT_DIR/}"
    local manifest_path="Release/scripts/$rel"

    local actual
    actual=$(shasum -a 256 "$file" | awk '{print $1}')
    local expected
    # shasum separates the hash and the path with two spaces; an awk
    # `$2` only catches paths with no spaces. Use substr to grab
    # everything after the first run of whitespace.
    expected=$(awk -v p="$manifest_path" 'index($0, p) {print substr($0, 1, index($0, "  ") - 1); exit}' "$manifest")
    [[ -z "$expected" ]] && { warn "no checksum for $manifest_path in manifest, skipping"; return 0; }
    if [[ "$actual" != "$expected" ]]; then
        fail "SHA256 mismatch for $file
  expected: $expected
  actual:   $actual"
    fi
    log "  SHA256 OK: $(basename "$file")"
}

# Are the pre-built bundles and asset files present?
have_prebuilt_bundles() {
    [[ -f "$SAVER_SRC/Contents/MacOS/JohnnyScreenSaver" ]] \
    && [[ -f "$APPEX_SRC/Contents/MacOS/JohnnyScreenSaver" ]]
}

have_prebuilt_assets() {
    [[ -f "$ASSETS_SRC/RESOURCE.MAP" ]] && [[ -f "$ASSETS_SRC/RESOURCE.001" ]]
}

# Prompt the user to point at the Sierra resource directory if it
# wasn't passed in.  Defaults to ~/Library/Application Support/Johnny
# Castaway Resources if it already has the files (re-install path).
prompt_for_assets() {
    if have_prebuilt_assets; then
        return 0
    fi
    if [[ -n "$RESOURCE_DIR" ]]; then
        if [[ ! -f "$RESOURCE_DIR/RESOURCE.MAP" ]] || [[ ! -f "$RESOURCE_DIR/RESOURCE.001" ]]; then
            fail "--resource-dir $RESOURCE_DIR does not contain RESOURCE.MAP and RESOURCE.001"
        fi
        ASSETS_SRC="$RESOURCE_DIR"
        return 0
    fi
    if [[ -f "$ASSETS_DST/RESOURCE.MAP" ]] && [[ -f "$ASSETS_DST/RESOURCE.001" ]]; then
        log "found existing assets in $ASSETS_DST (re-using)"
        ASSETS_SRC="$ASSETS_DST"
        return 0
    fi
    cat <<EOF
This is the public-repo installer. The Sierra resource files
(RESOURCE.MAP, RESOURCE.001) are NOT vendored here — they are
(c) 1992 Sierra/Dynamix and live only in the private backup repo
giattijunior/johnny-castaway-macos-screensaver.

To finish the install, point this script at a directory containing
both files. You can either:

  1. Use a pre-built release from the private repo
     (giattijunior/johnny-castaway-macos-screensaver/releases/tag/v1.0.0)
     which bundles them.

  2. Re-run with --resource-dir /path/to/folder/containing/RESOURCE.MAP

  3. Mount a Sierra installer (DOSBox SCID SIERRA/SCRANTIC/), copy
     the two files to a folder of your choosing, and re-run with
     --resource-dir /that/folder

EOF
    fail "RESOURCE.MAP / RESOURCE.001 not found locally. Re-run with --resource-dir."
}

# -----------------------------------------------------------------------
# Verify-only mode
# -----------------------------------------------------------------------

if [[ $DO_VERIFY -eq 1 ]]; then
    log "verifying release artifacts"
    for f in \
        "$ASSETS_SRC/RESOURCE.MAP" \
        "$ASSETS_SRC/RESOURCE.001" \
        "$SAVER_SRC/Contents/MacOS/JohnnyScreenSaver" \
        "$APPEX_SRC/Contents/MacOS/JohnnyScreenSaver"
    do
        [[ -f "$f" ]] || { warn "missing: $f (skipped, public repo may not vendored it)"; continue; }
        verify_sha256 "$f"
    done
    log "verify complete"
    exit 0
fi

# -----------------------------------------------------------------------
# Uninstall
# -----------------------------------------------------------------------

if [[ $DO_UNINSTALL -eq 1 ]]; then
    log "uninstalling Johnny Castaway screensaver"
    [[ -e "$SAVER_DST" ]] && rm -rf "$SAVER_DST" && log "  removed $SAVER_DST"
    [[ -e "$APPEX_DST" ]] && rm -rf "$APPEX_DST" && log "  removed $APPEX_DST"
    [[ -e "$ASSETS_DST" ]] && rm -rf "$ASSETS_DST" && log "  removed $ASSETS_DST"
    [[ -e "$SETTINGS_JSON" ]] && rm -f "$SETTINGS_JSON" && log "  removed $SETTINGS_JSON"
    killall legacyScreenSaver 2>/dev/null && log "  killed legacyScreenSaver" || true
    killall ScreenSaverEngine  2>/dev/null && log "  killed ScreenSaverEngine"  || true
    killall cfprefsd            2>/dev/null && log "  killed cfprefsd"            || true
    log "uninstall complete. Reopen System Settings → Screen Saver to refresh."
    exit 0
fi

# -----------------------------------------------------------------------
# Pre-flight checks
# -----------------------------------------------------------------------

log "Johnny Castaway screensaver installer (public-repo / BYO build)"
echo

# macOS version gate. The .appex path requires Tahoe (26.5+); the .saver
# works back to Sonoma. We install both regardless — the system picks the
# correct one for the current macOS.
MACOS_MAJOR=$(sw_vers -productVersion | cut -d. -f1)
log "macOS $(sw_vers -productVersion) detected"

# If we're on Tahoe but the user doesn't have Full Disk Access for
# Terminal, lsregister may not be able to write to the LaunchServices
# db. We don't need lsregister for .appex (ExtensionKit auto-indexes),
# but we warn anyway because a related bug on Tahoe may bite the .saver.
if [[ $MACOS_MAJOR -ge 26 ]]; then
    log "Tahoe detected — the .appex will be loaded by ExtensionKit; the .saver is the legacy fallback"
fi

# Tools required
for tool in sw_vers shasum codesign xattr; do
    command -v "$tool" >/dev/null || fail "missing required tool: $tool"
done

# -----------------------------------------------------------------------
# If pre-built bundles aren't present, build from source
# -----------------------------------------------------------------------

if ! have_prebuilt_bundles; then
    log "no pre-built bundles in $SCRIPT_DIR/../bundles — building from source"
    command -v swift >/dev/null || fail "swift not found; cannot build from source"
    command -v xcodebuild >/dev/null || warn "xcodebuild not found; build may fail"

    cd "$REPO_ROOT/Apps/JohnnyScreenSaver"
    bash Scripts/build-saver.sh || fail "build-saver.sh failed"
    bash Scripts/build-appex.sh || fail "build-appex.sh failed"

    # Copy freshly built bundles into Release/bundles/
    mkdir -p "$SCRIPT_DIR/../bundles"
    cp -R "$REPO_ROOT/Apps/JohnnyScreenSaver/build/JohnnyScreenSaver.saver" "$SCRIPT_DIR/../bundles/"
    cp -R "$REPO_ROOT/Apps/JohnnyScreenSaver/build/JohnnyScreenSaver.appex" "$SCRIPT_DIR/../bundles/"
    log "rebuilt bundles staged at $SCRIPT_DIR/../bundles/"
    cd "$SCRIPT_DIR"
    DO_BUILD_FROM_SOURCE=0
fi

# -----------------------------------------------------------------------
# Source the resource files (BYO-resources check)
# -----------------------------------------------------------------------

prompt_for_assets

# -----------------------------------------------------------------------
# Verify what's about to be installed
# -----------------------------------------------------------------------

for f in \
    "$ASSETS_SRC/RESOURCE.MAP" \
    "$ASSETS_SRC/RESOURCE.001" \
    "$SAVER_SRC/Contents/MacOS/JohnnyScreenSaver" \
    "$APPEX_SRC/Contents/MacOS/JohnnyScreenSaver"
do
    if [[ ! -f "$f" ]]; then
        fail "missing artifact: $f
hint: re-run with --build-from-source to build it locally, or
      restore the Release/ tree from the git repo:
        git checkout -- Release/"
    fi
    verify_sha256 "$f"
done

# -----------------------------------------------------------------------
# Stop any running screensaver processes so they re-load on next activation
# -----------------------------------------------------------------------

log "stopping running screensaver processes (will respawn on demand)"
killall legacyScreenSaver 2>/dev/null || true
killall ScreenSaverEngine  2>/dev/null || true
killall cfprefsd            2>/dev/null || true

# -----------------------------------------------------------------------
# Install assets
# -----------------------------------------------------------------------

log "installing Sierra resource bundle"
rm -rf "$ASSETS_DST"
mkdir -p "$ASSETS_DST"
cp "$ASSETS_SRC/RESOURCE.MAP" "$ASSETS_DST/"
cp "$ASSETS_SRC/RESOURCE.001" "$ASSETS_DST/"
log "  $ASSETS_DST/"
ls -l "$ASSETS_DST"

# -----------------------------------------------------------------------
# Install .saver (legacy)
# -----------------------------------------------------------------------

log "installing legacy .saver bundle"
mkdir -p "$(dirname "$SAVER_DST")"
rm -rf "$SAVER_DST"
cp -R "$SAVER_SRC" "$SAVER_DST"
xattr -cr "$SAVER_DST"
codesign --force --deep --sign - "$SAVER_DST" 2>&1 | head -3
log "  $SAVER_DST"

# -----------------------------------------------------------------------
# Install .appex (Tahoe / ExtensionKit)
# -----------------------------------------------------------------------

log "installing Tahoe .appex bundle"
mkdir -p "$(dirname "$APPEX_DST")"
rm -rf "$APPEX_DST"
cp -R "$APPEX_SRC" "$APPEX_DST"
xattr -cr "$APPEX_DST"

# Re-sign with the bundled entitlements file. The .appex shipped in the
# release is already signed, but we re-sign here so the user gets a
# fresh signature tied to the entitlements even if the bundle was
# re-built or moved. The entitlements file is required for ExtensionKit
# to index the bundle (com.apple.security.app-sandbox +
# com.apple.developer.extension-host.screensaver).
if [[ -f "$ENTITLEMENTS_SRC" ]]; then
    codesign --force --deep --sign - --entitlements "$ENTITLEMENTS_SRC" "$APPEX_DST" 2>&1 | head -3
else
    warn "entitlements file not found at $ENTITLEMENTS_SRC; signing without entitlements"
    codesign --force --deep --sign - "$APPEX_DST" 2>&1 | head -3
fi
log "  $APPEX_DST"

# -----------------------------------------------------------------------
# Write settings.json so the screensaver finds the resource folder
# without the user having to NSOpenPanel through the configure sheet.
# -----------------------------------------------------------------------

log "writing settings.json so the screensaver finds the resources on first run"
mkdir -p "$SETTINGS_DIR"
cat > "$SETTINGS_JSON" <<EOF
{
  "resourceFolderPath" : "$ASSETS_DST",
  "soundEnabled" : true,
  "animationSpeed" : 1.0,
  "forceStoryDay" : 0,
  "forceHoliday" : 0,
  "fidelityMode" : "fixed",
  "scalingMode" : "fit",
  "crtFilterEnabled" : false,
  "clockOverlayEnabled" : false,
  "batterySavingEnabled" : true,
  "useRemasteredAudio" : false,
  "showDebugOverlay" : false,
  "progressStoryDay" : 1,
  "progressLastCalendarDay" : -1
}
EOF
log "  $SETTINGS_JSON"

# -----------------------------------------------------------------------
# Tell cfprefsd to re-read prefs
# -----------------------------------------------------------------------

log "refreshing cfprefsd"
killall cfprefsd 2>/dev/null || true
sleep 1

# -----------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------

log ""
log "============================================================"
log "  Johnny Castaway screensaver installed"
log "============================================================"
log ""
log "Installed artifacts:"
log "  $ASSETS_DST"
log "    RESOURCE.MAP ($(wc -c < "$ASSETS_DST/RESOURCE.MAP" | tr -d ' ') bytes)"
log "    RESOURCE.001 ($(wc -c < "$ASSETS_DST/RESOURCE.001" | tr -d ' ') bytes)"
log "  $SAVER_DST"
log "  $APPEX_DST"
log "  $SETTINGS_JSON"
log ""
log "Next steps:"
log "  1. Open System Settings → Screen Saver"
log "  2. Select 'Johnny Castaway' from the list"
log "  3. Click 'Screen Saver Options…' to configure (sound, CRT filter, etc.)"
log ""
log "If Johnny Castaway does not appear in the list, see the troubleshooting"
log "section of the README at docs/TROUBLESHOOTING.md (TODO)."
log ""
log "To uninstall: bash Release/scripts/Install.sh --uninstall"

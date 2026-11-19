#!/bin/bash
# Builds Tessera.app with the Xcode Command Line Tools (no Xcode project needed).
# Usage: bash build.sh            -> build/Tessera.app
#        bash build.sh --install  -> also copies to /Applications and launches it
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Tessera.app"
ARCH="$(uname -m)"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || echo unknown)"
SWIFT_VERSION="$(swiftc --version 2>/dev/null | head -1 | sed -E 's/.*Swift version ([0-9.]+).*/\1/')"
echo "macOS SDK ${SDK_VERSION}, Swift ${SWIFT_VERSION}"
if [[ "${SDK_VERSION%%.*}" =~ ^[0-9]+$ ]] && (( ${SDK_VERSION%%.*} >= 26 )); then
    echo "Liquid Glass: native (macOS 26 SDK)"
else
    echo "Liquid Glass: emulated. For the native effect, install the Command Line Tools for Xcode 26"
    echo "  (System Settings > General > Software Update, or: softwareupdate --list)"
fi

echo "Compiling for ${ARCH}..."
swiftc -O -parse-as-library \
    -target "${ARCH}-apple-macos13.0" \
    -o "$APP/Contents/MacOS/Tessera" \
    Sources/*.swift

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    # Quit the running copy (and the app's former name, Toolbox) and wait until it is
    # really gone, otherwise "open" would just bring the old process forward.
    for NAME in Tessera Toolbox; do
        pkill -x "$NAME" 2>/dev/null || true
        for _ in $(seq 1 50); do
            pgrep -x "$NAME" >/dev/null || break
            sleep 0.1
        done
        pkill -9 -x "$NAME" 2>/dev/null || true
    done
    # Remove the copy installed under the former name, so only Tessera remains.
    rm -rf /Applications/Toolbox.app
    rm -rf /Applications/Tessera.app
    cp -R "$APP" /Applications/
    open -n /Applications/Tessera.app
    echo "Installed to /Applications and launched (build $(date '+%H:%M:%S'))."
fi

#!/usr/bin/env bash
# Build MatosicMenubar.app from the SPM executable.
# Usage: ./build.sh
# Output: dist/MatosicMenubar.app  +  dist/MatosicMenubar.zip
set -euo pipefail

APP_NAME="MatosicMenubar"
BUNDLE_ID="com.matosic.menubar"
DISPLAY_NAME="Matosic Macropad"
DIST_DIR="dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"

cd "$(dirname "$0")"

echo "==> swift build -c release"
swift build -c release

EXEC_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"
if [[ ! -x "${EXEC_PATH}" ]]; then
    echo "error: built executable not found at ${EXEC_PATH}" >&2
    exit 1
fi

echo "==> assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${EXEC_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP_DIR}/Contents/Info.plist"

# Apple wants every .app to have at least an ad-hoc signature so Gatekeeper
# considers it "signed by no one" rather than "actively tampered with."
# Without this, double-clicking on a fresh download silently fails on
# macOS 14+ instead of showing the right-click-to-Open path.
echo "==> ad-hoc codesign"
codesign --force --deep --sign - "${APP_DIR}"

echo "==> zipping ${DIST_DIR}/${APP_NAME}.zip"
rm -f "${DIST_DIR}/${APP_NAME}.zip"
# Use ditto so the resulting zip preserves macOS metadata + works with `unzip`
# on any platform (rather than only on macOS-aware tools).
ditto -c -k --sequesterRsrc --keepParent "${APP_DIR}" "${DIST_DIR}/${APP_NAME}.zip"

echo ""
echo "Built:  ${APP_DIR}"
echo "Zipped: ${DIST_DIR}/${APP_NAME}.zip"
echo ""
echo "To test:   open ${APP_DIR}"
echo "To ship:   upload ${DIST_DIR}/${APP_NAME}.zip to a GitHub Release"

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

# Build per-arch slices separately, then lipo them into a universal binary.
# `swift build --arch arm64 --arch x86_64` *can* produce a fat binary in one
# pass but the output path moves around between SPM versions; building each
# slice and lipo'ing is explicit, reproducible, and works on any toolchain.
echo "==> swift build -c release --arch arm64"
swift build -c release --arch arm64
ARM64_EXEC="$(swift build -c release --arch arm64 --show-bin-path)/${APP_NAME}"

echo "==> swift build -c release --arch x86_64"
swift build -c release --arch x86_64
X86_64_EXEC="$(swift build -c release --arch x86_64 --show-bin-path)/${APP_NAME}"

if [[ ! -x "${ARM64_EXEC}" || ! -x "${X86_64_EXEC}" ]]; then
    echo "error: per-arch executables not found." >&2
    echo "  arm64:  ${ARM64_EXEC}" >&2
    echo "  x86_64: ${X86_64_EXEC}" >&2
    exit 1
fi

echo "==> lipo arm64 + x86_64 into universal binary"
mkdir -p "${DIST_DIR}"
EXEC_PATH="${DIST_DIR}/${APP_NAME}-universal"
lipo -create "${ARM64_EXEC}" "${X86_64_EXEC}" -output "${EXEC_PATH}"
lipo -info "${EXEC_PATH}"

echo "==> assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${EXEC_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP_DIR}/Contents/Info.plist"

# Copy the SPM-generated resource bundle into the .app. AppDelegate loads
# the bird PDF via Bundle.module, which looks for this bundle in
# Bundle.main.resourceURL (= Contents/Resources/ inside an .app).
# Both arch slices produce identical bundles (it's just data) — grab arm64's.
RESOURCE_BUNDLE_NAME="${APP_NAME}_${APP_NAME}.bundle"
ARM64_RESOURCE_BUNDLE="$(swift build -c release --arch arm64 --show-bin-path)/${RESOURCE_BUNDLE_NAME}"
if [[ ! -d "${ARM64_RESOURCE_BUNDLE}" ]]; then
    echo "error: SPM resource bundle not found at ${ARM64_RESOURCE_BUNDLE}" >&2
    echo "  (did you remove resources: from Package.swift?)" >&2
    exit 1
fi
cp -R "${ARM64_RESOURCE_BUNDLE}" "${APP_DIR}/Contents/Resources/"

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

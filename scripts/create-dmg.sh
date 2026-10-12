#!/bin/bash
set -euo pipefail

# Script to build a branded macOS Disk Image (.dmg) and .zip release archive
# Output: dist/ProPack-<version>.dmg and dist/ProPack-<version>.zip

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${PROJECT_DIR}/dist"
APP_NAME="ProPack"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONFIG_DIR="${PROJECT_DIR}/Config"
BG_TIFF="${CONFIG_DIR}/dmg-background.tiff"
BG_PNG="${CONFIG_DIR}/dmg-background.png"

# 1. Resolve Version
APP_VERSION="${APP_VERSION:-}"
if [ -z "${APP_VERSION}" ]; then
    if command -v node >/dev/null 2>&1 && [ -f "${PROJECT_DIR}/scripts/get-version.js" ]; then
        APP_VERSION="$(node "${PROJECT_DIR}/scripts/get-version.js" 2>/dev/null || echo "0.1.0")"
    else
        APP_VERSION="0.1.0"
    fi
fi

DMG_NAME="${APP_NAME}-${APP_VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
ZIP_NAME="${APP_NAME}-${APP_VERSION}.zip"
ZIP_PATH="${DIST_DIR}/${ZIP_NAME}"
STAGING_DIR="${DIST_DIR}/.dmg-staging"

echo "==> Building installer DMG for ${APP_NAME} v${APP_VERSION}..."

# 2. Ensure ProPack.app exists
if [ ! -d "${APP_BUNDLE}" ]; then
    echo "==> ${APP_BUNDLE} not found. Running build-app.sh..."
    APP_VERSION="${APP_VERSION}" "${PROJECT_DIR}/scripts/build-app.sh"
fi

# 3. Ensure DMG background assets exist
if [ ! -f "${BG_TIFF}" ] || [ ! -f "${BG_PNG}" ]; then
    echo "==> Generating branded DMG background assets..."
    mkdir -p "${PROJECT_DIR}/.build/modcache"
    swiftc \
        -swift-version 6 \
        -target arm64-apple-macos14.0 \
        -module-cache-path "${PROJECT_DIR}/.build/modcache" \
        -o "${PROJECT_DIR}/.build/gen-dmg-bg" \
        "${PROJECT_DIR}/scripts/generate-dmg-background.swift"
    "${PROJECT_DIR}/.build/gen-dmg-bg"
fi

# 4. Resolve create-dmg utility
CREATE_DMG_BIN="$(command -v create-dmg || echo "")"
if [ -z "${CREATE_DMG_BIN}" ] && [ -x "/opt/homebrew/bin/create-dmg" ]; then
    CREATE_DMG_BIN="/opt/homebrew/bin/create-dmg"
elif [ -z "${CREATE_DMG_BIN}" ] && [ -x "/usr/local/bin/create-dmg" ]; then
    CREATE_DMG_BIN="/usr/local/bin/create-dmg"
fi

if [ -z "${CREATE_DMG_BIN}" ] && command -v brew >/dev/null 2>&1; then
    echo "==> create-dmg not found. Attempting install via Homebrew..."
    brew install create-dmg || true
    CREATE_DMG_BIN="$(command -v create-dmg || echo "")"
fi

# 5. Clean previous artifacts & prepare staging
rm -rf "${STAGING_DIR}" "${DMG_PATH}" "${ZIP_PATH}"
mkdir -p "${STAGING_DIR}"

if [ -n "${CREATE_DMG_BIN}" ] && [ -x "${CREATE_DMG_BIN}" ]; then
    echo "==> Building branded DMG with create-dmg..."
    cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"

    BG_IMAGE="${BG_TIFF}"
    [ -f "${BG_IMAGE}" ] || BG_IMAGE="${BG_PNG}"

    VOLICON_ARGS=()
    if [ -f "${PROJECT_DIR}/ProPack/AppIcon.icns" ]; then
        VOLICON_ARGS=(--volicon "${PROJECT_DIR}/ProPack/AppIcon.icns")
    fi

    # create-dmg creates the DMG with custom background, window bounds, and drag-and-drop link
    "${CREATE_DMG_BIN}" \
        --volname "${APP_NAME}" \
        "${VOLICON_ARGS[@]}" \
        --background "${BG_IMAGE}" \
        --window-pos 200 120 \
        --window-size 660 400 \
        --icon-size 128 \
        --text-size 12 \
        --icon "${APP_NAME}.app" 180 205 \
        --hide-extension "${APP_NAME}.app" \
        --app-drop-link 480 205 \
        --format UDZO \
        --overwrite \
        "${DMG_PATH}" \
        "${STAGING_DIR}" || {
            echo "==> create-dmg failed; falling back to standard hdiutil creation..."
            rm -rf "${STAGING_DIR}" "${DMG_PATH}"
            mkdir -p "${STAGING_DIR}"
            cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"
            ln -s /Applications "${STAGING_DIR}/Applications"
            hdiutil create \
                -volname "${APP_NAME} ${APP_VERSION}" \
                -srcfolder "${STAGING_DIR}" \
                -ov \
                -format UDZO \
                "${DMG_PATH}"
        }
else
    echo "==> create-dmg not available; building standard DMG via hdiutil..."
    cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"
    ln -s /Applications "${STAGING_DIR}/Applications"
    hdiutil create \
        -volname "${APP_NAME} ${APP_VERSION}" \
        -srcfolder "${STAGING_DIR}" \
        -ov \
        -format UDZO \
        "${DMG_PATH}"
fi

# 6. Code sign DMG (ad-hoc by default, or with SIGNING_IDENTITY)
SIGN_ID="${SIGNING_IDENTITY:--}"
echo "==> Signing DMG with identity: '${SIGN_ID}'..."
codesign --force --sign "${SIGN_ID}" "${DMG_PATH}"

# 7. Create standalone release ZIP using ditto
echo "==> Creating standalone release ZIP: ${ZIP_PATH}..."
/usr/bin/ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

# 8. Clean up staging
rm -rf "${STAGING_DIR}"

echo "==> Release artifacts ready:"
echo "    DMG: ${DMG_PATH}"
echo "    ZIP: ${ZIP_PATH}"

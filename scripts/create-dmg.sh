#!/bin/bash
set -euo pipefail

# Script to build a standalone compressed macOS Disk Image (.dmg) and .zip release archive
# Output: dist/ProPack-<version>.dmg and dist/ProPack-<version>.zip

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${PROJECT_DIR}/dist"
APP_NAME="ProPack"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"

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

# 2. Ensure ProPack.app exists and has the matching version
if [ ! -d "${APP_BUNDLE}" ]; then
    echo "==> ${APP_BUNDLE} not found. Running build-app.sh..."
    APP_VERSION="${APP_VERSION}" "${PROJECT_DIR}/scripts/build-app.sh"
fi

# 3. Prepare staging directory
rm -rf "${STAGING_DIR}" "${DMG_PATH}" "${ZIP_PATH}"
mkdir -p "${STAGING_DIR}"

echo "==> Staging ${APP_NAME}.app and /Applications symlink..."
cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

# 4. Create DMG via hdiutil
echo "==> Creating compressed disk image: ${DMG_PATH}..."
hdiutil create \
    -volname "${APP_NAME} ${APP_VERSION}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

# 5. Code sign DMG (ad-hoc by default, or with SIGNING_IDENTITY)
SIGN_ID="${SIGNING_IDENTITY:--}"
echo "==> Signing DMG with identity: '${SIGN_ID}'..."
codesign --force --sign "${SIGN_ID}" "${DMG_PATH}"

# 6. Create standard release zip using ditto
echo "==> Creating standalone release ZIP: ${ZIP_PATH}..."
/usr/bin/ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

# Clean up staging
rm -rf "${STAGING_DIR}"

echo "==> Release artifacts ready:"
echo "    DMG: ${DMG_PATH}"
echo "    ZIP: ${ZIP_PATH}"

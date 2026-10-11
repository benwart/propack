#!/bin/bash
set -euo pipefail

# Build script for ProPack.app
# Outputs an installable macOS application bundle to dist/ProPack.app

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${PROJECT_DIR}/dist"
APP_NAME="ProPack"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
MODCACHE_DIR="${PROJECT_DIR}/.build/modcache"

echo "==> Building ${APP_NAME}.app bundle..."

# Clean previous build artifacts
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${MODCACHE_DIR}"

# 1. Compile Swift executable
echo "==> Compiling Swift sources (macOS 14.0+ target, Swift 6)..."
swiftc \
    -swift-version 6 \
    -target arm64-apple-macos14.0 \
    -parse-as-library \
    -O \
    -module-cache-path "${MODCACHE_DIR}" \
    -o "${MACOS_DIR}/${APP_NAME}" \
    "${PROJECT_DIR}/ProPack"/*.swift

# 2. Copy AppIcon.icns
if [ -f "${PROJECT_DIR}/ProPack/AppIcon.icns" ]; then
    echo "==> Copying AppIcon.icns..."
    cp "${PROJECT_DIR}/ProPack/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# 3. Generate Info.plist
echo "==> Generating Contents/Info.plist..."
cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ProPack</string>
    <key>CFBundleIdentifier</key>
    <string>com.benwart.propack</string>
    <key>CFBundleName</key>
    <string>ProPack</string>
    <key>CFBundleDisplayName</key>
    <string>ProPack</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>ProPack reads ProPresenter presentation files from your Documents folder to include them in exported playlist packages.</string>
</dict>
</plist>
EOF

# 4. Code Sign
# Accepts optional SIGNING_IDENTITY env var. Defaults to ad-hoc ("-")
SIGN_ID="${SIGNING_IDENTITY:--}"
ENTITLEMENTS="${PROJECT_DIR}/Config/ProPack.entitlements"

echo "==> Code signing with identity: '${SIGN_ID}'..."
codesign --force --deep --sign "${SIGN_ID}" \
    --options runtime \
    --entitlements "${ENTITLEMENTS}" \
    "${APP_BUNDLE}"

echo "==> Build complete! Output: ${APP_BUNDLE}"
echo "    You can run or install it by moving to /Applications:"
echo "    cp -R \"${APP_BUNDLE}\" /Applications/"

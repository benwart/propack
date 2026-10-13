#!/bin/bash
set -euo pipefail

# Script to compile and run the ProPack automated unit test suite
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/.build"
MODCACHE_DIR="${BUILD_DIR}/modcache"
TEST_BINARY="${BUILD_DIR}/propack-test-runner"

mkdir -p "${BUILD_DIR}" "${MODCACHE_DIR}"

echo "==> Compiling ProPack unit test suite..."
swiftc \
    -swift-version 5 \
    -target arm64-apple-macos14.0 \
    -module-cache-path "${MODCACHE_DIR}" \
    -O \
    -o "${TEST_BINARY}" \
    "${PROJECT_DIR}/ProPack/ProcessRunner.swift" \
    "${PROJECT_DIR}/ProPack/ProPresenterClient.swift" \
    "${PROJECT_DIR}/ProPack/LibraryLocator.swift" \
    "${PROJECT_DIR}/ProPack/MediaLocator.swift" \
    "${PROJECT_DIR}/ProPack/ThemeAndFontLocator.swift" \
    "${PROJECT_DIR}/ProPack/TransferHistory.swift" \
    "${PROJECT_DIR}/ProPack/ExportService.swift" \
    "${PROJECT_DIR}/ProPack/ImportService.swift" \
    "${PROJECT_DIR}/Tests"/*.swift

echo "==> Running test suite..."
"${TEST_BINARY}"

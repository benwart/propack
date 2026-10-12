# ProPack Makefile
# Builds standalone ProPack.app bundle without opening Xcode.

APP_NAME = ProPack
DIST_DIR = dist
APP_BUNDLE = $(DIST_DIR)/$(APP_NAME).app
SIGNING_IDENTITY ?= -

.PHONY: all app run clean install uninstall help docs docs-serve

all: app

## app: Build and code-sign the standalone ProPack.app bundle
app:
	@echo "==> Building $(APP_BUNDLE)..."
	@SIGNING_IDENTITY="$(SIGNING_IDENTITY)" ./scripts/build-app.sh

## run: Build and launch ProPack.app
run: app
	@echo "==> Launching $(APP_BUNDLE)..."
	@open $(APP_BUNDLE)

## install: Install ProPack.app into /Applications
install: app
	@echo "==> Installing $(APP_BUNDLE) to /Applications..."
	@rm -rf /Applications/$(APP_NAME).app
	@cp -R $(APP_BUNDLE) /Applications/
	@touch /Applications/$(APP_NAME).app
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/$(APP_NAME).app 2>/dev/null || true
	@killall Dock 2>/dev/null || true
	@echo "==> Installed successfully to /Applications/$(APP_NAME).app (icon cache refreshed)"

## uninstall: Remove ProPack.app, unregister file extensions, and clear preferences
uninstall:
	@echo "==> Uninstalling $(APP_NAME)..."
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u /Applications/$(APP_NAME).app 2>/dev/null || true
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u $(APP_BUNDLE) 2>/dev/null || true
	@rm -rf /Applications/$(APP_NAME).app $(DIST_DIR)
	@defaults delete com.benwart.propack 2>/dev/null || true
	@rm -rf "$${TMPDIR:-/tmp/}ProPack"
	@echo "==> $(APP_NAME) successfully uninstalled and unreferenced from LaunchServices."

## docs: Build documentation site using uv
docs:
	@echo "==> Building documentation site with uv..."
	@uv run --group docs mkdocs build --strict

## docs-serve: Serve documentation locally with hot reloading using uv
docs-serve:
	@echo "==> Serving documentation with uv at http://127.0.0.1:8000..."
	@uv run --group docs mkdocs serve

## clean: Remove dist/ and build artifacts
clean:
	@echo "==> Cleaning build artifacts..."
	@rm -rf $(DIST_DIR) site/ .build/modcache .build/*.iconset .venv/

## help: Display this help message
help:
	@echo "Usage: make [target] [SIGNING_IDENTITY='...']"
	@echo ""
	@echo "Targets:"
	@sed -n 's/^## //p' $(MAKEFILE_LIST) | column -t -s ':'

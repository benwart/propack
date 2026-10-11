# ProPack Makefile
# Builds standalone ProPack.app bundle without opening Xcode.

APP_NAME = ProPack
DIST_DIR = dist
APP_BUNDLE = $(DIST_DIR)/$(APP_NAME).app
SIGNING_IDENTITY ?= -

.PHONY: all app run clean install help

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
	@cp -R $(APP_BUNDLE) /Applications/
	@echo "==> Installed successfully to /Applications/$(APP_NAME).app"

## clean: Remove dist/ and build artifacts
clean:
	@echo "==> Cleaning build artifacts..."
	@rm -rf $(DIST_DIR) .build/modcache .build/*.iconset

## help: Display this help message
help:
	@echo "Usage: make [target] [SIGNING_IDENTITY='...']"
	@echo ""
	@echo "Targets:"
	@sed -n 's/^## //p' $(MAKEFILE_LIST) | column -t -s ':'

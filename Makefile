# Speak — Build & Package
# Usage:
#   make build       Build debug binary via SPM
#   make release     Build release binary via SPM
#   make app         Build a release .app bundle via xcodebuild
#   make dmg         Package the .app into a DMG
#   make check       Build, then validate .app bundle (used by CI)
#   make clean       Remove build artifacts

APP_NAME     := Speak
BUNDLE_ID    := com.speak.app
SCHEME       := Speak
PROJECT      := Speak/Speak.xcodeproj
BUILD_DIR    := build
APP_PATH     := $(BUILD_DIR)/$(APP_NAME).app
DMG_PATH     := $(BUILD_DIR)/$(APP_NAME).dmg
VERSION      := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Speak/Speak/Info.plist 2>/dev/null || echo "0.1.0")

.PHONY: build release app dmg check clean

# --- SPM (for development) ---

build:
	cd Speak && swift build

release:
	cd Speak && swift build -c release

# --- xcodebuild (for distribution) ---

app:
	@mkdir -p $(BUILD_DIR)
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(BUILD_DIR)/DerivedData \
		-archivePath $(BUILD_DIR)/$(APP_NAME).xcarchive \
		archive \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_ALLOWED=YES
	@# Export the .app from the archive
	@cp -R $(BUILD_DIR)/$(APP_NAME).xcarchive/Products/Applications/$(APP_NAME).app $(APP_PATH)
	@echo "Built: $(APP_PATH)"

# --- DMG packaging ---

dmg: app
	@./scripts/create-dmg.sh $(APP_PATH) $(DMG_PATH) $(VERSION)

# --- CI check (build + validate bundle) ---

check: app
	@echo "── Checking executable exists"
	@test -f $(APP_PATH)/Contents/MacOS/$(APP_NAME) || { echo "FAIL: missing executable"; exit 1; }
	@echo "── Checking Info.plist exists"
	@test -f $(APP_PATH)/Contents/Info.plist || { echo "FAIL: missing Info.plist"; exit 1; }
	@echo "── Checking bundle identifier"
	@BUNDLE_ID=$$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" $(APP_PATH)/Contents/Info.plist); \
		echo "   Bundle ID: $$BUNDLE_ID"; \
		test -n "$$BUNDLE_ID" || { echo "FAIL: empty bundle identifier"; exit 1; }
	@echo "── Checking linked frameworks"
	@for fw in Speech AVFoundation AppKit CoreGraphics; do \
		otool -L $(APP_PATH)/Contents/MacOS/$(APP_NAME) | grep -q "$$fw" \
			|| { echo "FAIL: $$fw not linked"; exit 1; }; \
	done
	@echo "── All checks passed"

# --- Cleanup ---

clean:
	rm -rf $(BUILD_DIR)
	rm -rf Speak/.build

# Speak — Build & Package
# Usage:
#   make build       Build debug binary via SPM
#   make release     Build release binary via SPM
#   make app         Build a release .app bundle via xcodebuild
#   make dmg         Package the .app into a DMG
#   make clean       Remove build artifacts

APP_NAME     := Speak
BUNDLE_ID    := com.speak.app
SCHEME       := Speak
PROJECT      := Speak/Speak.xcodeproj
BUILD_DIR    := build
APP_PATH     := $(BUILD_DIR)/$(APP_NAME).app
DMG_PATH     := $(BUILD_DIR)/$(APP_NAME).dmg
VERSION      := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Speak/Speak/Info.plist 2>/dev/null || echo "0.1.0")

.PHONY: build release app dmg clean

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

# --- Cleanup ---

clean:
	rm -rf $(BUILD_DIR)
	rm -rf Speak/.build

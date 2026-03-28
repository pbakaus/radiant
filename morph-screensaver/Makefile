SUFFIX := $(shell date +%H%M%S)
PRODUCT_NAME := MorphSS$(SUFFIX)
BUNDLE_NAME := $(PRODUCT_NAME).saver
BUILD_DIR := build
BUNDLE_DIR := $(BUILD_DIR)/$(BUNDLE_NAME)
CONTENTS_DIR := $(BUNDLE_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
INSTALL_DIR := $(HOME)/Library/Screen Savers

SWIFT_SOURCE := Sources/MorphScreenSaverView.swift
METAL_SOURCE := Sources/Shaders.metal
MIN_MACOS := 14.0
SDK_PATH := $(shell xcrun --show-sdk-path)

ARCHS := arm64 x86_64

.PHONY: build install uninstall clean test

build: $(BUNDLE_DIR)

$(BUNDLE_DIR): $(SWIFT_SOURCE) $(METAL_SOURCE) Info.plist
	@echo "==> Building $(BUNDLE_NAME)..."
	@rm -rf $(BUILD_DIR)
	@mkdir -p $(MACOS_DIR) $(RESOURCES_DIR)

	@# Metal shaders: try pre-compile, fall back to bundling source
	@echo "  Compiling Metal shaders..."
	@if xcrun metal -c $(METAL_SOURCE) -o $(BUILD_DIR)/Shaders.air 2>/dev/null && \
	    xcrun metallib $(BUILD_DIR)/Shaders.air -o $(BUILD_DIR)/default.metallib 2>/dev/null; then \
		echo "  Metal shaders pre-compiled"; \
		cp $(BUILD_DIR)/default.metallib $(RESOURCES_DIR)/default.metallib; \
	else \
		echo "  Bundling .metal source for runtime compilation"; \
		cp $(METAL_SOURCE) $(RESOURCES_DIR)/Shaders.metal; \
	fi

	@# Compile Swift for each architecture
	@for arch in $(ARCHS); do \
		echo "  Compiling Swift for $$arch..."; \
		xcrun swiftc \
			-emit-library \
			-module-name MorphScreenSaver \
			-sdk $(SDK_PATH) \
			-target $$arch-apple-macos$(MIN_MACOS) \
			-framework ScreenSaver \
			-framework Metal \
			-framework QuartzCore \
			-framework AppKit \
			-framework Foundation \
			-o $(BUILD_DIR)/MorphScreenSaver-$$arch \
			$(SWIFT_SOURCE) || exit 1; \
	done

	@# Universal binary
	@echo "  Creating universal binary..."
	@lipo -create \
		$(BUILD_DIR)/MorphScreenSaver-arm64 \
		$(BUILD_DIR)/MorphScreenSaver-x86_64 \
		-output $(MACOS_DIR)/$(PRODUCT_NAME)
	@rm -f $(BUILD_DIR)/MorphScreenSaver-arm64 $(BUILD_DIR)/MorphScreenSaver-x86_64

	@# Info.plist with correct executable name and timestamped display name
	@sed -e 's|<string>MorphScreenSaver</string>|<string>$(PRODUCT_NAME)</string>|g' \
	     -e 's|<string>Morph Screensaver</string>|<string>Morph $(SUFFIX)</string>|g' \
	     Info.plist > $(CONTENTS_DIR)/Info.plist

	@# Ad-hoc code sign (required on modern macOS)
	@codesign --force --sign - $(MACOS_DIR)/$(PRODUCT_NAME)

	@echo "==> Built: $(BUNDLE_DIR)"

install: build
	@echo "==> Installing to ~/Library/Screen Savers/..."
	@rm -rf "$(INSTALL_DIR)"/MorphS*.saver
	@cp -R $(BUNDLE_DIR) "$(INSTALL_DIR)/$(BUNDLE_NAME)"
	@killall -9 legacyScreenSaver 2>/dev/null || true
	@killall -9 WallpaperAgent 2>/dev/null || true
	@echo "==> Installed. Open System Settings > Screen Saver to select $(PRODUCT_NAME)."

test: install
	@echo "==> Opening System Settings > Screen Saver..."
	@open "x-apple.systempreferences:com.apple.ScreenSaver-Settings"

uninstall:
	@echo "==> Uninstalling..."
	@rm -rf "$(INSTALL_DIR)"/MorphS*.saver
	@echo "==> Done."

clean:
	@echo "==> Cleaning..."
	@rm -rf $(BUILD_DIR)
	@echo "==> Clean."

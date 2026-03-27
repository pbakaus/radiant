SUFFIX := $(shell date +%H%M%S)
PRODUCT_NAME := RadiantSS$(SUFFIX)
BUNDLE_NAME := $(PRODUCT_NAME).saver
BUILD_DIR := build
BUNDLE_DIR := $(BUILD_DIR)/$(BUNDLE_NAME)
CONTENTS_DIR := $(BUNDLE_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
INSTALL_DIR := $(HOME)/Library/Screen Savers

SWIFT_SOURCES := $(wildcard Sources/*.swift)
METAL_SOURCES := $(wildcard Sources/Shaders/*.metal) \
                 $(wildcard Sources/Shaders/fragment/*.metal) \
                 $(wildcard Sources/Shaders/compute/*.metal)
MIN_MACOS := 14.0
SDK_PATH := $(shell xcrun --show-sdk-path)

ARCHS := arm64 x86_64

.PHONY: build install uninstall clean test

build: $(BUNDLE_DIR)

$(BUNDLE_DIR): $(SWIFT_SOURCES) $(METAL_SOURCES) Info.plist
	@echo "==> Building $(BUNDLE_NAME)..."
	@rm -rf $(BUILD_DIR)
	@mkdir -p $(MACOS_DIR) $(RESOURCES_DIR)

	@# Metal shaders: compile each .metal to .air, link into metallib
	@echo "  Compiling Metal shaders..."
	@mkdir -p $(BUILD_DIR)/air
	@METAL_OK=true; \
	for src in $(METAL_SOURCES); do \
		base=$$(basename $$src .metal); \
		if [ "$$base" = "Common" ]; then continue; fi; \
		echo "    $$base.metal -> $$base.air"; \
		xcrun metal -c $$src -I Sources/Shaders -o $(BUILD_DIR)/air/$$base.air 2>/dev/null || { METAL_OK=false; break; }; \
	done; \
	if [ "$$METAL_OK" = "true" ]; then \
		echo "  Linking metallib..."; \
		xcrun metallib $(BUILD_DIR)/air/*.air -o $(BUILD_DIR)/default.metallib 2>/dev/null && \
		cp $(BUILD_DIR)/default.metallib $(RESOURCES_DIR)/default.metallib && \
		echo "  Metal shaders pre-compiled"; \
	else \
		echo "  Metal toolchain unavailable — bundling .metal sources for runtime compilation"; \
		for src in $(METAL_SOURCES); do cp $$src $(RESOURCES_DIR)/; done; \
	fi

	@# Compile Swift for each architecture
	@for arch in $(ARCHS); do \
		echo "  Compiling Swift for $$arch..."; \
		xcrun swiftc \
			-emit-library \
			-module-name RadiantScreenSaver \
			-sdk $(SDK_PATH) \
			-target $$arch-apple-macos$(MIN_MACOS) \
			-framework ScreenSaver \
			-framework Metal \
			-framework QuartzCore \
			-framework AppKit \
			-framework Foundation \
			-framework CoreVideo \
			-o $(BUILD_DIR)/RadiantScreenSaver-$$arch \
			$(SWIFT_SOURCES) || exit 1; \
	done

	@# Universal binary
	@echo "  Creating universal binary..."
	@lipo -create \
		$(BUILD_DIR)/RadiantScreenSaver-arm64 \
		$(BUILD_DIR)/RadiantScreenSaver-x86_64 \
		-output $(MACOS_DIR)/$(PRODUCT_NAME)
	@rm -f $(BUILD_DIR)/RadiantScreenSaver-arm64 $(BUILD_DIR)/RadiantScreenSaver-x86_64

	@# Info.plist with correct executable name + timestamped display name
	@sed -e 's|<string>RadiantScreenSaver</string>|<string>$(PRODUCT_NAME)</string>|g' \
	     -e 's|<string>Radiant Gallery</string>|<string>Radiant $(SUFFIX)</string>|g' \
	     Info.plist > $(CONTENTS_DIR)/Info.plist

	@# Ad-hoc code sign
	@codesign --force --sign - $(MACOS_DIR)/$(PRODUCT_NAME)

	@echo "==> Built: $(BUNDLE_DIR)"

install: build
	@echo "==> Installing to ~/Library/Screen Savers/..."
	@rm -rf "$(INSTALL_DIR)"/RadiantS*.saver
	@cp -R $(BUNDLE_DIR) "$(INSTALL_DIR)/$(BUNDLE_NAME)"
	@killall -9 legacyScreenSaver 2>/dev/null || true
	@killall -9 WallpaperAgent 2>/dev/null || true
	@echo "==> Installed. Open System Settings > Screen Saver to select $(PRODUCT_NAME)."

test: install
	@echo "==> Opening System Settings > Screen Saver..."
	@open "x-apple.systempreferences:com.apple.ScreenSaver-Settings"

uninstall:
	@echo "==> Uninstalling..."
	@rm -rf "$(INSTALL_DIR)"/RadiantS*.saver
	@echo "==> Done."

clean:
	@echo "==> Cleaning..."
	@rm -rf $(BUILD_DIR)
	@echo "==> Clean."

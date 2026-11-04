APP_NAME := PersonifyDesk
BUNDLE_ID := com.local.personifydesk
APP := dist/$(APP_NAME).app

UNAME_S := $(shell uname -s)
SWIFT := bash scripts/with-sdk.sh swift
SWIFT_FLAGS :=

ifeq ($(UNAME_S),Darwin)
export MACOSX_DEPLOYMENT_TARGET := 14.0
DEV_DIR := $(shell xcode-select -p 2>/dev/null)
TEST_PLUGIN := /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
ifneq ($(findstring CommandLineTools,$(DEV_DIR)),)
ifneq ($(wildcard $(TEST_PLUGIN)),)
SWIFT_FLAGS += -Xswiftc -plugin-path -Xswiftc $(TEST_PLUGIN)
endif
endif
endif

.PHONY: test app verify clean

test:
	$(SWIFT) test $(SWIFT_FLAGS)
	@if grep -R -n "999996" Sources/PersonifyCore; then \
		echo "999996 must stay out of the core library. It is only the editable connect-sheet suggestion."; \
		exit 1; \
	fi

app:
	@if [ "$(UNAME_S)" != "Darwin" ]; then \
		echo "make app needs macOS with Swift 6.4 Command Line Tools."; \
		exit 1; \
	fi
	$(SWIFT) build -c release --product $(APP_NAME) $(SWIFT_FLAGS)
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	python3 scripts/render-app-icon.py --master packaging/AppIcon-1024.png --iconset dist/PersonifyDesk.iconset
	iconutil -c icns dist/PersonifyDesk.iconset -o "$(APP)/Contents/Resources/AppIcon.icns"
	cp .build/release/$(APP_NAME) "$(APP)/Contents/MacOS/$(APP_NAME)"
	cp packaging/Info.plist "$(APP)/Contents/Info.plist"
	printf 'APPL????' > "$(APP)/Contents/PkgInfo"
	chmod 755 "$(APP)/Contents/MacOS/$(APP_NAME)"
	bash scripts/codesign-app.sh "$(APP)" "$(BUNDLE_ID)"

verify: app

clean:
	$(SWIFT) package clean || true
	rm -rf dist .build

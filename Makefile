.PHONY: help fmt fmt-check fmt-version lint test test-app test-package build run clean ci generate hooks js js-install js-typecheck coverage

PROJECT := Noter.xcodeproj
SCHEME  := Noter
DEST    := platform=macOS
JS_DIR  := Packages/MarkdownEditor/JS
PACKAGE := Packages/MarkdownEditor
SWIFTFORMAT_VERSION := $(shell tr -d '[:space:]' < .swiftformat-version)

help:
	@echo "Targets:"
	@echo "  make generate     - Generate Noter.xcodeproj via xcodegen"
	@echo "  make hooks        - Install lefthook git hooks"
	@echo "  make fmt          - SwiftFormat all sources"
	@echo "  make fmt-check    - SwiftFormat in lint mode (no writes)"
	@echo "  make fmt-version  - Warn if local SwiftFormat differs from the pin"
	@echo "  make lint         - SwiftLint --strict"
	@echo "  make test         - Run app + package tests"
	@echo "  make coverage     - Run app tests and print per-target coverage"
	@echo "  make build        - Release build"
	@echo "  make run          - Build and launch app"
	@echo "  make js           - Rebuild the CodeMirror bundle"
	@echo "  make js-typecheck - Typecheck the TypeScript sources"
	@echo "  make ci           - Everything CI runs, in CI's order"
	@echo "  make clean        - Clean build artifacts"

generate:
	xcodegen generate

hooks:
	lefthook install

# SwiftFormat changes its default ruleset between releases, so a version that
# disagrees with CI's pin will either reformat code CI rejects, or pass code CI
# fails. Warn rather than block: the message is enough to explain a CI failure.
fmt-version:
	@installed="$$(swiftformat --version 2>/dev/null)"; \
	if [ -z "$$installed" ]; then \
		echo "⚠️  SwiftFormat is not installed. This repo pins $(SWIFTFORMAT_VERSION)."; \
	elif [ "$$installed" != "$(SWIFTFORMAT_VERSION)" ]; then \
		echo "⚠️  SwiftFormat $$installed is installed, but this repo pins $(SWIFTFORMAT_VERSION)."; \
		echo "    CI uses the pinned version, so formatting results may differ."; \
		echo "    Get it: https://github.com/nicklockwood/SwiftFormat/releases/tag/$(SWIFTFORMAT_VERSION)"; \
	fi

fmt: fmt-version
	swiftformat .

fmt-check: fmt-version
	swiftformat --lint .

lint:
	swiftlint --strict

js-install:
	cd $(JS_DIR) && npm install

js-typecheck:
	cd $(JS_DIR) && npm run typecheck

js:
	cd $(JS_DIR) && npm run build

test-package:
	swift test --package-path $(PACKAGE)

test-app:
	set -o pipefail && xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' | xcbeautify

test: test-package test-app

coverage:
	set -o pipefail && xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-enableCodeCoverage YES -resultBundlePath TestResults.xcresult | xcbeautify
	@xcrun xccov view --report --only-targets TestResults.xcresult

build:
	set -o pipefail && xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -destination '$(DEST)' build | xcbeautify

run: build
	@APP_PATH=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -showBuildSettings 2>/dev/null | awk -F'= ' '/CODESIGNING_FOLDER_PATH/ {print $$2; exit}'); \
	open -n "$$APP_PATH"

clean:
	xcodebuild clean -project $(PROJECT) -scheme $(SCHEME)
	rm -rf .build DerivedData TestResults.xcresult

# Mirrors .github/workflows/ci.yml so a green `make ci` means a green pipeline.
ci: js-typecheck js fmt-check lint test build

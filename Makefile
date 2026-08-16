.PHONY: help fmt fmt-check lint test test-app test-package build run clean ci generate hooks js js-install js-typecheck coverage

PROJECT := Noter.xcodeproj
SCHEME  := Noter
DEST    := platform=macOS
JS_DIR  := Packages/MarkdownEditor/JS
PACKAGE := Packages/MarkdownEditor

help:
	@echo "Targets:"
	@echo "  make generate     - Generate Noter.xcodeproj via xcodegen"
	@echo "  make hooks        - Install lefthook git hooks"
	@echo "  make fmt          - SwiftFormat all sources"
	@echo "  make fmt-check    - SwiftFormat in lint mode (no writes)"
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

fmt:
	swiftformat .

fmt-check:
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

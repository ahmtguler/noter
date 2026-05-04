.PHONY: help fmt lint test build run clean ci generate hooks

PROJECT := Noter.xcodeproj
SCHEME  := Noter
DEST    := platform=macOS

help:
	@echo "Targets:"
	@echo "  make generate  - Generate Noter.xcodeproj via xcodegen"
	@echo "  make hooks     - Install lefthook git hooks"
	@echo "  make fmt       - SwiftFormat all sources"
	@echo "  make lint      - SwiftLint --strict"
	@echo "  make test      - Run tests"
	@echo "  make build     - Release build"
	@echo "  make run       - Build and launch app"
	@echo "  make ci        - lint + test + build (what CI runs)"
	@echo "  make clean     - xcodebuild clean"

generate:
	xcodegen generate

hooks:
	lefthook install

fmt:
	swiftformat .

lint:
	swiftlint --strict

test:
	set -o pipefail && xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' | xcbeautify

build:
	set -o pipefail && xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -destination '$(DEST)' build | xcbeautify

run: build
	@APP_PATH=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -showBuildSettings 2>/dev/null | awk -F'= ' '/CODESIGNING_FOLDER_PATH/ {print $$2; exit}'); \
	open -n "$$APP_PATH"

clean:
	xcodebuild clean -project $(PROJECT) -scheme $(SCHEME)
	rm -rf .build DerivedData

ci: lint test build

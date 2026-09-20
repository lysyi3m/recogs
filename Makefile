# Recogs — common tasks.
# Requires: xcodegen (brew install xcodegen)

PROJECT := Recogs.xcodeproj
SCHEME  := Recogs
PACKAGE := DiscogsKit

.DEFAULT_GOAL := help
.PHONY: help generate test test-package test-app build build-ios probe probe-cdn clean

help: ## List available targets
	@grep -E '^[a-z][a-zA-Z-]*:.*##' $(MAKEFILE_LIST) | sed -E 's/:.*## / — /' | sort

generate: ## Regenerate the Xcode project from project.yml
	xcodegen generate

test: test-package test-app ## Run every test suite

test-package: ## Run the DiscogsKit unit tests
	swift test --package-path $(PACKAGE)

test-app: generate ## Run the app's cache and image tests
	xcodebuild test -project "$(PROJECT)" -scheme "$(SCHEME)" \
		-destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

build: generate ## Build the app for macOS (unsigned compile check)
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Debug \
		-destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

build-ios: generate ## Build the app for the iOS Simulator (unsigned compile check)
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Debug \
		-destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

# Hits the real Discogs API with the token in .env. Dev-only; the app reads the Keychain.
probe: ## Smoke-test DiscogsKit against the live API
	swift run --package-path $(PACKAGE) discogs-probe

probe-cdn: ## Measure whether CDN image loads consume the API rate limit
	swift run --package-path $(PACKAGE) discogs-probe --cdn-check

clean: ## Remove build artifacts
	rm -rf build $(PACKAGE)/.build

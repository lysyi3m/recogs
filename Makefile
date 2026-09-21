# Recogs — common tasks.
# Requires: xcodegen (brew install xcodegen)

PROJECT := Recogs.xcodeproj
SCHEME  := Recogs
PACKAGE := DiscogsKit
QUERY   ?= remain in light
LOCAL_XCCONFIG := Config/Local.xcconfig

.DEFAULT_GOAL := help
.PHONY: help generate local-config test test-package test-app build build-ios probe probe-cdn probe-release probe-search clean

help: ## List available targets
	@grep -E '^[a-z][a-zA-Z-]*:.*##' $(MAKEFILE_LIST) | sed -E 's/:.*## / — /' | sort

generate: local-config ## Regenerate the Xcode project from project.yml
	xcodegen generate

# Xcode cannot read .env, so the machine-local settings it needs are projected into an xcconfig
# that Config/Base.xcconfig includes. This keeps .env the single place to set DEVELOPMENT_TEAM,
# for both `xcodebuild` and a plain Cmd-R in Xcode.
local-config: ## Project machine-local settings from .env into Config/Local.xcconfig
	@mkdir -p Config
	@printf '// Generated from .env by `make generate`. Do not edit, do not commit.\n' > $(LOCAL_XCCONFIG)
	@if [ -f .env ]; then \
		grep -E '^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=' .env \
			| sed -E 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*/DEVELOPMENT_TEAM = /' \
			>> $(LOCAL_XCCONFIG) || true; \
	fi
	@grep -q DEVELOPMENT_TEAM $(LOCAL_XCCONFIG) \
		&& echo "✓ DEVELOPMENT_TEAM from .env" \
		|| echo "• no DEVELOPMENT_TEAM in .env — signing will need a team picked in Xcode"

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

probe-release: ## Fetch one real release with its tracklist
	swift run --package-path $(PACKAGE) discogs-probe --release

probe-search: ## Search Discogs releases (QUERY="remain in light")
	swift run --package-path $(PACKAGE) discogs-probe --search "$(QUERY)"

clean: ## Remove build artifacts
	rm -rf build $(PACKAGE)/.build

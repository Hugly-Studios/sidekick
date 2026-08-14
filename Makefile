APP_NAME := Sidekick
BUNDLE_ID := com.hugly.sidekick
WORKSPACE := $(APP_NAME).xcworkspace
DERIVED := build
DEBUG_APP := $(DERIVED)/Build/Products/Debug/$(APP_NAME).app
SOURCES := Apps Core Features Tuist Project.swift Tuist.swift
export PATH := $(HOME)/.local/bin:$(PATH)
MISE := mise exec --
XCODEBUILD := xcodebuild -workspace $(WORKSPACE) -scheme $(APP_NAME) \
	-destination 'platform=macOS' -derivedDataPath $(DERIVED)

.DEFAULT_GOAL := help
.PHONY: help setup generate xcode build run restart stop test lint fmt verify \
	doctor snapshots snapshot restore install uninstall purge reset-permissions \
	logs clean update new-module dead-code smoke

help: ## Show available commands
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

setup: ## First run: tools, signing, dependencies, Xcode project
	scripts/bootstrap.sh

generate: ## Regenerate the Xcode project (needed after adding a module)
	scripts/version.sh
	$(MISE) tuist generate --no-open

xcode: ## Regenerate and open in Xcode
	scripts/version.sh
	$(MISE) tuist generate

build: generate ## Build the Debug app
	$(XCODEBUILD) -configuration Debug -quiet build

run: build restart ## Build, then restart the Debug app

restart: ## Restart the Debug app without rebuilding
	@pkill -x $(APP_NAME) >/dev/null 2>&1 || true
	@sleep 0.5
	open $(DEBUG_APP)

stop: ## Quit any running copy
	@scripts/sidekick.sh quit >/dev/null 2>&1 || true
	@osascript -e 'quit app "$(APP_NAME)"' >/dev/null 2>&1 || true
	@pkill -x $(APP_NAME) >/dev/null 2>&1 || true

test: generate ## Run unit tests
	@mkdir -p $(DERIVED)
	@set -o pipefail; \
		$(XCODEBUILD) -configuration Debug test 2>&1 \
		| $(MISE) xcbeautify --renderer terminal \
		| tee $(DERIVED)/test.log

lint: ## Check formatting and safety lint
	xcrun swift-format lint --strict --recursive --parallel $(SOURCES)
	$(MISE) swiftlint lint --strict --quiet

fmt: ## Reformat sources
	xcrun swift-format format --in-place --recursive --parallel $(SOURCES)

verify: generate ## Format, lint, build and test — the single PR gate
	xcrun swift-format lint --strict --recursive --parallel $(SOURCES)
	$(MISE) swiftlint lint --strict --quiet
	@mkdir -p $(DERIVED)
	@set -o pipefail; \
		$(XCODEBUILD) -configuration Debug test 2>&1 \
		| $(MISE) xcbeautify --renderer terminal

doctor: ## Report how the app is installed and whether it is reachable
	@scripts/sidekick.sh doctor --json

snapshots: ## List saved desktop layouts
	@scripts/sidekick.sh run workspaces.list --json

snapshot: ## Save the current desktop layout (NAME=... optional)
	@scripts/sidekick.sh run workspaces.capture $(if $(NAME),--arg "$(NAME)") --json

restore: ## Restore a layout (NAME=... or the default one)
	@scripts/sidekick.sh run workspaces.restore $(if $(NAME),--arg "$(NAME)") --json

install: ## Build Release and install to /Applications
	scripts/install.sh

uninstall: ## Remove the installed copy, keep settings
	scripts/uninstall.sh

purge: ## Remove the installed copy, settings and permission grants
	scripts/uninstall.sh --purge

reset-permissions: ## Forget granted permissions (to retest the first run)
	tccutil reset All $(BUNDLE_ID)

logs: ## Stream the app's log output
	log stream --style compact --predicate 'subsystem == "$(BUNDLE_ID)"'

update: ## Pull, install and smoke-test on this machine
	git pull --ff-only
	$(MAKE) install
	scripts/smoke.sh

new-module: ## Scaffold a feature module (NAME=Awake)
	@test -n "$(NAME)" || (echo "usage: make new-module NAME=Awake" >&2; exit 2)
	scripts/new-module.sh "$(NAME)"

dead-code: ## Scan for unused code (manual — SwiftUI false positives)
	$(MISE) periphery scan --workspace $(WORKSPACE) --schemes $(APP_NAME) || \
		echo "periphery is optional; install it with: mise use periphery"

smoke: ## End-to-end check of the installed app
	scripts/smoke.sh

clean: ## Delete build output and the generated project
	rm -rf $(DERIVED) $(WORKSPACE) $(APP_NAME).xcodeproj Derived

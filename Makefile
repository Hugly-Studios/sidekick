APP_NAME := Sidekick
BUNDLE_ID := com.hugly.sidekick
WORKSPACE := $(APP_NAME).xcworkspace
DERIVED := build
DEBUG_APP := $(DERIVED)/Build/Products/Debug/$(APP_NAME).app
SOURCES := Apps Core Tuist Project.swift Tuist.swift
XCODEBUILD := xcodebuild -workspace $(WORKSPACE) -scheme $(APP_NAME) \
	-destination 'platform=macOS' -derivedDataPath $(DERIVED)

.DEFAULT_GOAL := help
.PHONY: help setup generate xcode build run restart stop test lint fmt doctor \
	install uninstall purge reset-permissions logs clean

help: ## Show available commands
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

setup: ## First run: signing identity, dependencies, Xcode project
	scripts/setup-signing.sh
	scripts/tuist.sh install
	scripts/tuist.sh generate --no-open

generate: ## Regenerate the Xcode project (needed after adding files)
	scripts/tuist.sh generate --no-open

xcode: ## Regenerate and open in Xcode
	scripts/tuist.sh generate

build: generate ## Build the Debug app
	$(XCODEBUILD) -configuration Debug -quiet build

run: build restart ## Build, then restart the Debug app

restart: ## Restart the Debug app without rebuilding
	@pkill -x $(APP_NAME) >/dev/null 2>&1 || true
	@sleep 0.5
	open $(DEBUG_APP)

stop: ## Quit any running copy
	@osascript -e 'quit app "$(APP_NAME)"' >/dev/null 2>&1 || true
	@pkill -x $(APP_NAME) >/dev/null 2>&1 || true

test: generate ## Run unit tests
	@mkdir -p $(DERIVED)
	@$(XCODEBUILD) -configuration Debug test >$(DERIVED)/test.log 2>&1; \
		status=$$?; \
		grep -E "✔|✘|Test run with|error:" $(DERIVED)/test.log || true; \
		exit $$status

lint: ## Check formatting
	xcrun swift-format lint --strict --recursive --parallel $(SOURCES)

fmt: ## Reformat sources
	xcrun swift-format format --in-place --recursive --parallel $(SOURCES)

doctor: ## Report how the app is installed and whether it is reachable
	@scripts/doctor.sh

snapshots: ## List saved desktop layouts
	@scripts/sidekick.sh --snapshots

snapshot: ## Save the current desktop layout (NAME=... optional)
	@scripts/sidekick.sh --capture $(NAME)

restore: ## Restore a layout (NAME=... or the default one)
	@scripts/sidekick.sh --restore $(NAME)

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

clean: ## Delete build output and the generated project
	rm -rf $(DERIVED) $(WORKSPACE) $(APP_NAME).xcodeproj Derived

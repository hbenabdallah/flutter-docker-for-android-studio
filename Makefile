.PHONY: help setup setup-sdk avd emulator scan tether tether-stop adb-wifi install build access doctor pub-get clean run test build-apk build-appbundle stop start restart logs setup-wrappers setup-env

# Docker Compose service name
SERVICE = android
CONTAINER = flutter-android-dev

# Load environment variables from .env file
-include .env
export

# Load FLUTTER_PROJECT_PATH from .env file if it exists, otherwise use current directory
FLUTTER_PROJECT_PATH ?= $(shell if [ -f .env ]; then grep -E '^FLUTTER_PROJECT_PATH=' .env | cut -d '=' -f2- | head -1; else echo $(CURDIR); fi)

# Host path of ./sdk, mounted at the same path in the container
SDK_PATH ?= $(CURDIR)/sdk
export SDK_PATH
export FLUTTER_PROJECT_PATH

# Load USER, USER_ID, GROUP_ID, HOME_PATH from .env
USER ?= $(shell whoami)
USER_ID ?= $(shell id -u)
GROUP_ID ?= $(shell id -g)
HOME_PATH ?= /home/$(USER)

# Host directory mounted at the same path in the container (flutter/dart work anywhere below it)
WORKSPACE_PATH ?= $(abspath $(CURDIR)/..)
export WORKSPACE_PATH

# Run a command in the container, in the Flutter project
EXEC = docker compose exec -w $(FLUTTER_PROJECT_PATH) $(SERVICE)

# Default Flutter command arguments
FLUTTER_ARGS ?=

# Help target
help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Installation and setup
setup-env: ## Detect and update .env file with user configuration
	@echo "Detecting user configuration..."
	@if [ ! -f .env ]; then \
		echo "Creating .env file from .env.example..."; \
		cp .env.example .env 2>/dev/null || touch .env; \
	fi
	@CURRENT_USER=$$(whoami); \
	CURRENT_UID=$$(id -u); \
	CURRENT_GID=$$(id -g); \
	CURRENT_HOME=/home/$$CURRENT_USER; \
	echo "Detected: USER=$$CURRENT_USER, USER_ID=$$CURRENT_UID, GROUP_ID=$$CURRENT_GID, HOME_PATH=$$CURRENT_HOME"; \
	if grep -q "^USER_ID=" .env 2>/dev/null; then \
		sed -i "s|^USER_ID=.*|USER_ID=$$CURRENT_UID|" .env; \
	else \
		echo "" >> .env; \
		echo "USER_ID=$$CURRENT_UID" >> .env; \
	fi; \
	if grep -q "^GROUP_ID=" .env 2>/dev/null; then \
		sed -i "s|^GROUP_ID=.*|GROUP_ID=$$CURRENT_GID|" .env; \
	else \
		echo "GROUP_ID=$$CURRENT_GID" >> .env; \
	fi; \
	if grep -q "^USER=" .env 2>/dev/null; then \
		sed -i "s|^USER=.*|USER=$$CURRENT_USER|" .env; \
	else \
		echo "USER=$$CURRENT_USER" >> .env; \
	fi; \
	if grep -q "^HOME_PATH=" .env 2>/dev/null; then \
		sed -i "s|^HOME_PATH=.*|HOME_PATH=$$CURRENT_HOME|" .env; \
	else \
		echo "HOME_PATH=$$CURRENT_HOME" >> .env; \
	fi; \
	if grep -q "^SDK_PATH=" .env 2>/dev/null; then \
		sed -i "s|^SDK_PATH=.*|SDK_PATH=$(CURDIR)/sdk|" .env; \
	else \
		echo "SDK_PATH=$(CURDIR)/sdk" >> .env; \
	fi; \
	if ! grep -q "^WORKSPACE_PATH=." .env 2>/dev/null; then \
		sed -i "/^WORKSPACE_PATH=/d" .env; \
		echo "WORKSPACE_PATH=$(abspath $(CURDIR)/..)" >> .env; \
	fi; \
	echo "Updated .env file with detected values"
	@echo ""
	@echo "Current .env configuration:"
	@grep -E '^(USER_ID|GROUP_ID|USER|HOME_PATH|FLUTTER_PROJECT_PATH|SDK_PATH|WORKSPACE_PATH)=' .env | sed 's/^/  /'

setup-wrappers: ## Replace sdk/flutter/bin/flutter and dart with Docker wrapper scripts
	@if [ ! -d "sdk/flutter" ]; then \
		echo "Error: sdk/flutter directory not found. Run 'make setup-sdk' first to export the SDKs."; \
		exit 1; \
	fi
	@if [ ! -w sdk/flutter/bin/flutter ] 2>/dev/null; then \
		echo "Warning: sdk/flutter files are owned by root."; \
		echo "         Run: sudo chown -R $$(whoami):$$(whoami) sdk/flutter"; \
		exit 1; \
	fi
	@for tool in flutter dart; do \
		if [ -f sdk/flutter/bin/$$tool ] && [ ! -f sdk/flutter/bin/$$tool.backup ]; then \
			cp sdk/flutter/bin/$$tool sdk/flutter/bin/$$tool.backup && \
			echo "Backed up original $$tool to sdk/flutter/bin/$$tool.backup"; \
		fi; \
		cp scripts/sdk-wrapper.sh sdk/flutter/bin/$$tool && chmod +x sdk/flutter/bin/$$tool && \
		echo "Created wrapper: sdk/flutter/bin/$$tool"; \
	done
	@echo ""
	@echo "Configure Android Studio:"
	@echo "  File → Settings → Languages & Frameworks → Flutter"
	@echo "  Flutter SDK path: $(CURDIR)/sdk/flutter"
	@echo ""
	@echo "Or add to your PATH:"
	@echo "  export PATH=\"$(CURDIR)/sdk/flutter/bin:\$$PATH\""

setup-sdk: build ## Export SDKs from Docker container into local sdk folder
	@echo "Exporting SDKs from Docker container into ./sdk..."
	@mkdir -p sdk $(HOME_PATH)/.pub-cache
	@docker compose run --rm \
		-v $(CURDIR)/sdk:/workspace/sdk \
		$(SERVICE) bash -lc '\
		  set -e; \
		  echo "Copying SDKs to /workspace/sdk ..."; \
		  rm -rf /workspace/sdk/java /workspace/sdk/android /workspace/sdk/flutter /workspace/sdk/dart; \
		  mkdir -p /workspace/sdk; \
		  cp -a /usr/lib/jvm/java-17-openjdk-amd64 /workspace/sdk/java; \
		  find /workspace/sdk/java -type l | while read l; do \
		    t=$$(readlink -f "$$l" || true); if [ -f "$$t" ]; then rm "$$l"; cp "$$t" "$$l"; fi; done; \
		  cp -a /opt/android-sdk /workspace/sdk/android; \
		  cp -a /opt/flutter /workspace/sdk/flutter; \
		  cp -a /opt/flutter/bin/cache/dart-sdk /workspace/sdk/dart; \
		  echo "SDKs exported to sdk folder"'

install: build ## Alias for build
	@echo "Installation complete!"

build: ## Build the Docker image
	@echo "Building Docker image..."
	docker compose build

# Container management
access: ## Access the container shell
	@echo "Accessing container..."
	$(EXEC) bash

start: ## Start the container and connect ADB (recreates to apply env changes)
	@echo "Starting container (force recreate to apply any docker-compose.yml changes)..."
	@mkdir -p $(HOME_PATH)/.pub-cache
	@case "$(FLUTTER_PROJECT_PATH)/" in "$(WORKSPACE_PATH)/"*) ;; \
		*) echo "Warning: FLUTTER_PROJECT_PATH ($(FLUTTER_PROJECT_PATH)) is not inside WORKSPACE_PATH ($(WORKSPACE_PATH))";; \
	esac
	@docker compose up -d --force-recreate --remove-orphans
	@echo "Waiting for container to be ready..."
	@sleep 2
	@if docker ps | grep -q flutter-android-dev; then \
		if docker exec flutter-android-dev bash -lc "adb devices" 2>/dev/null | grep -qE "^[0-9a-f]{8,}\s+(device|online)"; then \
			echo "Connecting ADB to host emulator..."; \
			docker exec flutter-android-dev bash -lc "adb connect host.docker.internal:5554 || true" 2>/dev/null || echo "Note: ADB connection failed."; \
		else \
			echo "No connected Android device detected. Skipping ADB connection."; \
		fi \
	else \
		echo "Warning: Container not running. Start it first with 'make start'."; \
	fi

stop: ## Stop the container
	@echo "Stopping container..."
	docker compose stop

restart: stop start ## Restart the container
	@echo "Container restarted"

logs: ## Show container logs
	docker compose logs -f $(SERVICE)

# Flutter commands
doctor: ## Run Flutter doctor
	@echo "Running Flutter doctor..."
	$(EXEC) flutter doctor $(FLUTTER_ARGS)

pub-get: ## Run Flutter pub get
	@echo "Running Flutter pub get..."
	$(EXEC) flutter pub get $(FLUTTER_ARGS)

pub-upgrade: ## Run Flutter pub upgrade
	@echo "Running Flutter pub upgrade..."
	$(EXEC) flutter pub upgrade $(FLUTTER_ARGS)

clean: ## Clean Flutter build files
	@echo "Cleaning Flutter build files..."
	$(EXEC) flutter clean $(FLUTTER_ARGS)

run: ## Run Flutter app (use FLUTTER_ARGS for device/target)
	@echo "Running Flutter app..."
	$(EXEC) flutter run $(FLUTTER_ARGS)

test: ## Run Flutter tests
	@echo "Running Flutter tests..."
	$(EXEC) flutter test $(FLUTTER_ARGS)

build-apk: ## Build Android APK (use FLUTTER_ARGS for release/debug)
	@echo "Building Android APK..."
	$(EXEC) flutter build apk $(FLUTTER_ARGS)

build-appbundle: ## Build Android App Bundle (use FLUTTER_ARGS for release/debug)
	@echo "Building Android App Bundle..."
	$(EXEC) flutter build appbundle $(FLUTTER_ARGS)

build-ios: ## Build iOS app (use FLUTTER_ARGS for release/debug)
	@echo "Building iOS app..."
	$(EXEC) flutter build ios $(FLUTTER_ARGS)

build-web: ## Build web app (use FLUTTER_ARGS for release/debug)
	@echo "Building web app..."
	$(EXEC) flutter build web $(FLUTTER_ARGS)

# Generic Flutter command runner
flutter: ## Run any Flutter command (use FLUTTER_ARGS="command args")
	@if [ -z "$(FLUTTER_ARGS)" ]; then \
		echo "Error: FLUTTER_ARGS is required. Example: make flutter FLUTTER_ARGS='create my_app'"; \
		exit 1; \
	fi
	@echo "Running: flutter $(FLUTTER_ARGS)"
	$(EXEC) flutter $(FLUTTER_ARGS)

# Version and info commands
version: ## Show Flutter version
	@echo "Flutter version:"
	$(EXEC) flutter --version

dart-version: ## Show Dart version
	@echo "Dart version:"
	$(EXEC) dart --version

java-version: ## Show Java version
	@echo "Java version:"
	$(EXEC) java -version

info: version dart-version java-version ## Show all version information

# Zebra MC330M emulator (AVD created in ~/.android/avd/Zebra_MC330M.avd)
AVD ?= Zebra_MC330M
EMULATOR_ACCEL ?= $(if $(wildcard /dev/kvm),auto,off)
# DataWedge intent action of your app (set it in .env), e.g. com.example.my_app.SCAN
SCAN_ACTION ?=

avd: ## Download the emulator + Android 8.1 image and create the Zebra MC330M AVD
	$(EXEC) sdkmanager "emulator" "system-images;android-27;google_apis;x86"
	SDK_PATH=$(SDK_PATH) AVD=$(AVD) ./scripts/create-avd.sh

emulator: ## Start the Zebra MC330M emulator on the host (software mode when /dev/kvm is missing)
	ANDROID_SDK_ROOT=$(SDK_PATH)/android $(SDK_PATH)/android/emulator/emulator -avd $(AVD) -no-audio -accel $(EMULATOR_ACCEL) -gpu swiftshader_indirect &

scan: ## Send a fake DataWedge scan to the app (CODE='barcode or JSON')
	@if [ -z "$$CODE" ]; then echo "Usage: make scan CODE='...'"; exit 1; fi
	@if [ -z "$(SCAN_ACTION)" ]; then echo "Error: set SCAN_ACTION in .env (DataWedge intent action of your app)"; exit 1; fi
	@code=$$(printf '%s' "$$CODE" | sed "s/'/'\\\\''/g"); \
	$(SDK_PATH)/android/platform-tools/adb shell "am broadcast -a $(SCAN_ACTION) \
		-c android.intent.category.DEFAULT --es com.symbol.datawedge.data_string '$$code'"

# Reverse tethering (gnirehtet): the device's traffic goes through adb and leaves from the laptop,
# so it uses the laptop's VPN (a hotspot only shares the plain connection). No root needed.
GNIREHTET_VERSION = 2.5.1
GNIREHTET_SHA256 = dee55499ca4fef00ce2559c767d2d8130163736d43fdbce753e923e75309c275
GNIREHTET_DIR = $(CURDIR)/sdk/gnirehtet
GNIREHTET = ADB=$(SDK_PATH)/android/platform-tools/adb GNIREHTET_APK=$(GNIREHTET_DIR)/gnirehtet.apk $(GNIREHTET_DIR)/gnirehtet
# DNS used by the device (default: the laptop's current DNS server, i.e. the VPN one)
TETHER_DNS := $(or $(TETHER_DNS),$(shell resolvectl status 2>/dev/null | awk '/Current DNS Server/ {print $$4; exit}'))
# adb serial of the device, required only when several devices are connected
DEVICE ?=

$(GNIREHTET_DIR)/gnirehtet:
	@echo "Downloading gnirehtet $(GNIREHTET_VERSION)..."
	@mkdir -p $(GNIREHTET_DIR)
	@tmp=$$(mktemp -d) && \
	curl -fsSL -o $$tmp/gnirehtet.zip https://github.com/Genymobile/gnirehtet/releases/download/v$(GNIREHTET_VERSION)/gnirehtet-rust-linux64-v$(GNIREHTET_VERSION).zip && \
	echo "$(GNIREHTET_SHA256)  $$tmp/gnirehtet.zip" | sha256sum -c --quiet && \
	unzip -q -o -j $$tmp/gnirehtet.zip -d $(GNIREHTET_DIR) && \
	rm -rf $$tmp

tether: $(GNIREHTET_DIR)/gnirehtet ## Share the laptop connection (and VPN) with the device over adb, Ctrl+C to stop (DEVICE=serial, TETHER_DNS=ip)
	@if [ -z "$(TETHER_DNS)" ]; then echo "Error: could not detect the DNS server, set TETHER_DNS=<ip>"; exit 1; fi
	@echo "Reverse tethering with DNS $(TETHER_DNS). Accept the VPN prompt on the device the first time."
	$(GNIREHTET) run $(DEVICE) -d $(TETHER_DNS)

tether-stop: $(GNIREHTET_DIR)/gnirehtet ## Stop reverse tethering on the device (DEVICE=serial)
	$(GNIREHTET) stop $(DEVICE)

adb-wifi: ## Switch the USB-connected device to adb over Wi-Fi (then unplug it and run make tether)
	@adb=$(SDK_PATH)/android/platform-tools/adb; \
	ip=$$($$adb $(if $(DEVICE),-s $(DEVICE)) shell ip -f inet addr show wlan0 | awk '/inet / {sub(/\/.*/, "", $$2); print $$2; exit}'); \
	if [ -z "$$ip" ]; then echo "Error: device not connected over USB, or not on Wi-Fi"; exit 1; fi; \
	$$adb $(if $(DEVICE),-s $(DEVICE)) tcpip 5555 && sleep 2 && $$adb connect $$ip:5555 && \
	echo "Unplug the device, then: make tether DEVICE=$$ip:5555"

# Android SDK commands
android-licenses: ## Accept Android SDK licenses
	@echo "Accepting Android SDK licenses..."
	$(EXEC) sdkmanager --licenses

# Cleanup commands
clean-all: clean ## Clean Flutter and remove containers/volumes
	@echo "Stopping and removing containers..."
	docker compose down -v
	@echo "Cleanup complete!"

# Quick setup: build and verify
setup: setup-env setup-sdk setup-wrappers start doctor ## Complete setup: detect env, export SDKs, create wrappers, start, and verify with doctor
	@echo ""
	@echo "Setup complete! Flutter SDK wrappers created."
	@echo ""
	@echo "Configure Android Studio:"
	@echo "  File → Settings → Languages & Frameworks → Flutter"
	@echo "  Flutter SDK path: $(CURDIR)/sdk/flutter"
	@echo ""
	@echo "  File → Settings → Build, Execution, Deployment → Build Tools → Gradle"
	@echo "  Gradle JDK: Use Gradle's default (Gradle runs inside container)"
	@echo ""
	@echo "Or add to your PATH:"
	@echo "  export PATH=\"$(CURDIR)/sdk/flutter/bin:\$$PATH\""
	@echo ""
	@echo "Run 'make access' to enter the container."


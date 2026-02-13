.PHONY: help install build access doctor pub-get clean run test build-apk build-appbundle stop start restart logs setup-wrappers setup-env

# Docker Compose service name
SERVICE = android
CONTAINER = flutter-android-dev

# Load environment variables from .env file
-include .env
export

# Load FLUTTER_PROJECT_PATH from .env file if it exists, otherwise use current directory
FLUTTER_PROJECT_PATH ?= $(shell if [ -f .env ]; then grep -E '^FLUTTER_PROJECT_PATH=' .env | cut -d '=' -f2- | head -1; else echo $(CURDIR); fi)
export FLUTTER_PROJECT_PATH

# Load USER, USER_ID, GROUP_ID, HOME_PATH from .env
USER ?= $(shell whoami)
USER_ID ?= $(shell id -u)
GROUP_ID ?= $(shell id -g)
HOME_PATH ?= /home/$(USER)

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
	echo "Updated .env file with detected values"
	@echo ""
	@echo "Current .env configuration:"
	@grep -E '^(USER_ID|GROUP_ID|USER|HOME_PATH|FLUTTER_PROJECT_PATH)=' .env | sed 's/^/  /'

setup-wrappers: ## Replace sdk/flutter/bin executables with Docker wrapper scripts
	@if [ -z "$(FLUTTER_PROJECT_PATH)" ]; then \
		echo "Error: FLUTTER_PROJECT_PATH is not set. Please create a .env file with:"; \
		echo "  FLUTTER_PROJECT_PATH=/path/to/your/project"; \
		exit 1; \
	fi
	@if [ ! -d "sdk/flutter" ]; then \
		echo "Error: sdk/flutter directory not found. Run 'make setup-sdk' first to export the SDKs."; \
		exit 1; \
	fi
	@echo "Replacing sdk/flutter/bin executables with Docker wrapper scripts..."
	@if [ ! -w sdk/flutter/bin/flutter ] 2>/dev/null; then \
		echo "Warning: sdk/flutter files are owned by root."; \
		echo "         Run: sudo chown -R $$(whoami):$$(whoami) sdk/flutter"; \
		echo "         Or run this command with sudo: sudo make setup-wrappers"; \
		exit 1; \
	fi
	@if [ -f sdk/flutter/bin/flutter ] && [ ! -f sdk/flutter/bin/flutter.backup ]; then \
		cp sdk/flutter/bin/flutter sdk/flutter/bin/flutter.backup && \
		echo "Backed up original flutter to sdk/flutter/bin/flutter.backup"; \
	fi
	@if [ -f sdk/flutter/bin/dart ] && [ ! -f sdk/flutter/bin/dart.backup ]; then \
		cp sdk/flutter/bin/dart sdk/flutter/bin/dart.backup && \
		echo "Backed up original dart to sdk/flutter/bin/dart.backup"; \
	fi
	@echo '#!/bin/bash' > sdk/flutter/bin/flutter
	@echo 'docker exec -i -w $(FLUTTER_PROJECT_PATH) flutter-android-dev flutter "$$@"' >> sdk/flutter/bin/flutter
	@chmod +x sdk/flutter/bin/flutter
	@echo "Created wrapper: sdk/flutter/bin/flutter"
	@echo '#!/bin/bash' > sdk/flutter/bin/dart
	@echo 'docker exec -i -w $(FLUTTER_PROJECT_PATH) flutter-android-dev dart "$$@"' >> sdk/flutter/bin/dart
	@chmod +x sdk/flutter/bin/dart
	@echo "Created wrapper: sdk/flutter/bin/dart"
	@if [ -f android/gradlew ] && [ ! -f android/gradlew.backup ]; then \
		cp android/gradlew android/gradlew.backup; \
		echo "Backed up original gradlew to gradlew.backup"; \
	fi
	@if [ -f android/gradlew.backup ]; then \
		mkdir -p android; \
		printf '%s\n%s\n%s\n' '#!/bin/bash' 'docker exec -i flutter-android-dev bash -c \' "  \"cd $(FLUTTER_PROJECT_PATH)/android && ./gradlew.backup \$$*\"" > android/gradlew; \
		chmod +x android/gradlew; \
		echo "Created android/gradlew wrapper"; \
	else \
		echo "Warning: android/gradlew.backup not found. Skipping gradlew wrapper creation."; \
		echo "         Create a Flutter project first or manually create android/gradlew.backup."; \
	fi
	@echo ""
	@echo "Wrapper scripts created in sdk/flutter/bin/"
	@echo ""
	@echo "Configure Android Studio:"
	@echo "  File → Settings → Languages & Frameworks → Flutter"
	@echo "  Flutter SDK path: $(FLUTTER_PROJECT_PATH)/sdk/flutter"
	@echo ""
	@echo "Or add to your PATH:"
	@echo "  export PATH=\"$(FLUTTER_PROJECT_PATH)/sdk/flutter/bin:\$$PATH\""

setup-sdk: build ## Export SDKs from Docker container into local sdk folder
	@echo "Exporting SDKs from Docker container into ./sdk..."
	@mkdir -p sdk
	@docker compose run --rm \
		-v $(CURDIR)/sdk:/workspace/sdk \
		$(SERVICE) bash -lc '\
		  set -e; \
		  echo "Copying SDKs to /workspace/sdk ..."; \
		  rm -rf /workspace/sdk/java /workspace/sdk/android /workspace/sdk/flutter /workspace/sdk/dart; \
		  mkdir -p /workspace/sdk; \
		  cp -a /usr/lib/jvm/java-17-openjdk-amd64 /workspace/sdk/java; \
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
	docker compose exec $(SERVICE) bash

start: ## Start the container and connect ADB (recreates to apply env changes)
	@echo "Starting container (force recreate to apply any docker-compose.yml changes)..."
	@docker compose up -d --force-recreate --remove-orphans
	@echo "Waiting for container to be ready..."
	@sleep 2
	@if docker ps | grep -q flutter-android-dev; then \
		echo "Connecting ADB to host emulator..."; \
		docker exec flutter-android-dev bash -lc "adb connect host.docker.internal:5554 || true" 2>/dev/null || echo "Note: ADB connection attempted. If emulator is not running, start it first."; \
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
	docker compose exec $(SERVICE) flutter doctor $(FLUTTER_ARGS)

pub-get: ## Run Flutter pub get
	@echo "Running Flutter pub get..."
	docker compose exec $(SERVICE) flutter pub get $(FLUTTER_ARGS)

pub-upgrade: ## Run Flutter pub upgrade
	@echo "Running Flutter pub upgrade..."
	docker compose exec $(SERVICE) flutter pub upgrade $(FLUTTER_ARGS)

clean: ## Clean Flutter build files
	@echo "Cleaning Flutter build files..."
	docker compose exec $(SERVICE) flutter clean $(FLUTTER_ARGS)

run: ## Run Flutter app (use FLUTTER_ARGS for device/target)
	@echo "Running Flutter app..."
	docker compose exec $(SERVICE) flutter run $(FLUTTER_ARGS)

test: ## Run Flutter tests
	@echo "Running Flutter tests..."
	docker compose exec $(SERVICE) flutter test $(FLUTTER_ARGS)

build-apk: ## Build Android APK (use FLUTTER_ARGS for release/debug)
	@echo "Building Android APK..."
	docker compose exec $(SERVICE) flutter build apk $(FLUTTER_ARGS)

build-appbundle: ## Build Android App Bundle (use FLUTTER_ARGS for release/debug)
	@echo "Building Android App Bundle..."
	docker compose exec $(SERVICE) flutter build appbundle $(FLUTTER_ARGS)

build-ios: ## Build iOS app (use FLUTTER_ARGS for release/debug)
	@echo "Building iOS app..."
	docker compose exec $(SERVICE) flutter build ios $(FLUTTER_ARGS)

build-web: ## Build web app (use FLUTTER_ARGS for release/debug)
	@echo "Building web app..."
	docker compose exec $(SERVICE) flutter build web $(FLUTTER_ARGS)

# Generic Flutter command runner
flutter: ## Run any Flutter command (use FLUTTER_ARGS="command args")
	@if [ -z "$(FLUTTER_ARGS)" ]; then \
		echo "Error: FLUTTER_ARGS is required. Example: make flutter FLUTTER_ARGS='create my_app'"; \
		exit 1; \
	fi
	@echo "Running: flutter $(FLUTTER_ARGS)"
	docker compose exec $(SERVICE) flutter $(FLUTTER_ARGS)

# Version and info commands
version: ## Show Flutter version
	@echo "Flutter version:"
	docker compose exec $(SERVICE) flutter --version

dart-version: ## Show Dart version
	@echo "Dart version:"
	docker compose exec $(SERVICE) dart --version

java-version: ## Show Java version
	@echo "Java version:"
	docker compose exec $(SERVICE) java -version

info: version dart-version java-version ## Show all version information

# Android SDK commands
android-licenses: ## Accept Android SDK licenses
	@echo "Accepting Android SDK licenses..."
	docker compose exec $(SERVICE) sdkmanager --licenses

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
	@echo "  Flutter SDK path: $(FLUTTER_PROJECT_PATH)/sdk/flutter"
	@echo ""
	@echo "  File → Settings → Build, Execution, Deployment → Build Tools → Gradle"
	@echo "  Gradle JDK: Use Gradle's default (Gradle runs inside container)"
	@echo ""
	@echo "Or add to your PATH:"
	@echo "  export PATH=\"$(FLUTTER_PROJECT_PATH)/sdk/flutter/bin:\$$PATH\""
	@echo ""
	@echo "Run 'make access' to enter the container."


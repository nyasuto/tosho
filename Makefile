# Tosho macOS Manga Viewer - Makefile
# Development and build automation

.PHONY: help build clean test lint format quality setup-dev all
.DEFAULT_GOAL := help

# Project Configuration
PROJECT_NAME = Tosho
SCHEME = Tosho
BUILD_DIR = build
XCODE_PROJECT = $(PROJECT_NAME).xcodeproj

# Build Configurations
BUILD_CONFIG_DEBUG = Debug
BUILD_CONFIG_RELEASE = Release

help: ## Show this help message
	@echo "Tosho macOS Manga Viewer - Development Commands"
	@echo "=============================================="
	@echo ""
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

setup-dev: ## Initial development environment setup
	@echo "Setting up development environment..."
	@if ! command -v swiftlint >/dev/null 2>&1; then \
		echo "Installing SwiftLint..."; \
		brew install swiftlint; \
	else \
		echo "SwiftLint already installed"; \
	fi
	@echo "Development environment ready!"

build: ## Build the project in Debug configuration
	@echo "Building $(PROJECT_NAME) (Debug)..."
	@xcodebuild -project $(XCODE_PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(BUILD_CONFIG_DEBUG) \
		-derivedDataPath $(BUILD_DIR) \
		build

build-release: ## Build the project in Release configuration
	@echo "Building $(PROJECT_NAME) (Release)..."
	@xcodebuild -project $(XCODE_PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(BUILD_CONFIG_RELEASE) \
		-derivedDataPath $(BUILD_DIR) \
		build

clean: ## Clean build artifacts
	@echo "Cleaning build artifacts..."
	@xcodebuild -project $(XCODE_PROJECT) \
		-scheme $(SCHEME) \
		clean
	@rm -rf $(BUILD_DIR)
	@echo "Clean complete"

test: ## Run unit tests
	@echo "Running tests..."
	@xcodebuild -project $(XCODE_PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(BUILD_CONFIG_DEBUG) \
		-derivedDataPath $(BUILD_DIR) \
		test

lint: ## Run SwiftLint
	@echo "Running SwiftLint..."
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint --config .swiftlint.yml lint; \
	else \
		echo "SwiftLint not installed. Run 'make setup-dev' first."; \
		exit 1; \
	fi

format: ## Auto-format code with SwiftLint
	@echo "Formatting code with SwiftLint..."
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint --config .swiftlint.yml --fix; \
	else \
		echo "SwiftLint not installed. Run 'make setup-dev' first."; \
		exit 1; \
	fi

check-syntax: ## Basic syntax checks
	@echo "Checking project file syntax..."
	@plutil -lint $(XCODE_PROJECT)/project.pbxproj && echo "✓ Xcode project syntax OK"
	@python3 -c "import yaml; yaml.safe_load(open('.github/dependabot.yml'))" && echo "✓ Dependabot YAML syntax OK"
	@find . -name "*.swift" -print0 | xargs -0 -I {} bash -c 'head -1 "{}" > /dev/null' && echo "✓ All Swift files readable"

quality: lint build ## Run all quality checks
	@echo "All quality checks completed!"

run: build ## Build and run the application
	@echo "Launching $(PROJECT_NAME)..."
	@open $(BUILD_DIR)/Build/Products/$(BUILD_CONFIG_DEBUG)/$(PROJECT_NAME).app

archive: ## Create a release archive
	@echo "Creating release archive..."
	@xcodebuild -project $(XCODE_PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(BUILD_CONFIG_RELEASE) \
		-derivedDataPath $(BUILD_DIR) \
		archive \
		-archivePath $(BUILD_DIR)/$(PROJECT_NAME).xcarchive

export: archive ## Export signed application
	@echo "Exporting application..."
	@xcodebuild -exportArchive \
		-archivePath $(BUILD_DIR)/$(PROJECT_NAME).xcarchive \
		-exportPath $(BUILD_DIR)/Export \
		-exportOptionsPlist ExportOptions.plist

dev-info: ## Show development environment information
	@echo "Development Environment Information"
	@echo "=================================="
	@echo "Project: $(PROJECT_NAME)"
	@echo "Scheme: $(SCHEME)"
	@echo "Xcode Project: $(XCODE_PROJECT)"
	@echo "Build Directory: $(BUILD_DIR)"
	@echo ""
	@echo "System Information:"
	@echo "- macOS: $$(sw_vers -productVersion)"
	@echo "- Xcode: $$(xcodebuild -version | head -1 || echo 'Not available')"
	@echo "- Swift: $$(swift --version | head -1 || echo 'Not available')"
	@echo "- SwiftLint: $$(swiftlint version 2>/dev/null || echo 'Not installed')"

all: clean quality build ## Clean, run quality checks, and build

# Development workflow targets
pr-ready: quality build test ## Prepare for pull request (quality + build + test)
	@echo "✅ Ready for pull request!"

ci: quality build ## CI/CD pipeline simulation
	@echo "✅ CI checks passed!"

# Quick development commands
q: quality  ## Quick alias for quality checks
b: build    ## Quick alias for build
c: clean    ## Quick alias for clean
r: run      ## Quick alias for run
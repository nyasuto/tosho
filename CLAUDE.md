# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Tosho (図書) is a native macOS manga viewer application built with SwiftUI. The project is currently in the planning/initial development stage.

## Technology Stack

- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI
- **Minimum OS**: macOS 14.0 (Sonoma)
- **Architecture**: MVVM
- **Development Tool**: Xcode 15.0+
- **Bundle ID**: com.personal.tosho

## Build and Development Commands

### Xcode Project Setup
```bash
# Create new Xcode project via Xcode GUI:
# File > New > Project > macOS > App
# Product Name: Tosho
# Bundle Identifier: com.personal.tosho
# Interface: SwiftUI
# Language: Swift
```

### Build Commands
```bash
# Command-line build
xcodebuild -scheme Tosho build

# Run tests
xcodebuild -scheme Tosho test

# Clean build
xcodebuild -scheme Tosho clean

# Build and run in Xcode
# Use Cmd+R in Xcode

# IMPORTANT: Always build after making changes
# This ensures code quality and catches errors early
open Tosho.xcodeproj && echo "Build with Cmd+B to verify changes"
```

## Quality Assurance

### Build Requirements
⚠️ **CRITICAL RULE**: After making any changes to the codebase, **ALWAYS** perform a build to verify:

1. **After code changes**:
   ```bash
   # Open project and build
   open Tosho.xcodeproj
   # Then press Cmd+B in Xcode to build
   ```

2. **Before committing**:
   ```bash
   # Verify build succeeds before git commit
   xcodebuild -scheme Tosho -configuration Debug build
   ```

3. **Build verification checklist**:
   - [ ] No compilation errors
   - [ ] No warnings (aim for zero warnings)
   - [ ] All Swift files compile successfully
   - [ ] Entitlements and resources are properly referenced

### Build Troubleshooting
- If build fails, check file references in Xcode project
- Verify all files exist at expected paths
- Check Info.plist and entitlements file paths
- Ensure all Swift files are added to target

## Project Architecture

### Core Components

The application follows MVVM architecture with these main components:

- **App/**: Application entry point and configuration
  - ToshoApp.swift: Main application delegate

- **Views/**: SwiftUI view components
  - ReaderView: Core manga reading interface
  - ThumbnailView: Gallery view for browsing pages
  - LibraryView: Manga library management
  - SettingsView: Application preferences

- **ViewModels/**: Business logic and state management
  - ReaderViewModel: Handles page navigation, zoom, and reading modes
  - LibraryViewModel: Manages manga collection and metadata

- **Models/**: Data structures
  - ToshoDocument: Represents a manga file/archive
  - Page: Individual page representation
  - ReadingProgress: Tracks user's reading position

- **Services/**: Core functionality providers
  - FileLoader: Handles file system operations
  - ImageCache: Performance-critical image caching
  - ArchiveExtractor: ZIP/RAR extraction logic

### Key Technical Decisions

1. **Image Loading**: Lazy loading with aggressive caching for smooth page transitions
2. **Archive Handling**: Stream-based extraction to minimize memory usage
3. **Navigation**: Keyboard shortcuts and trackpad gestures for power users
4. **Performance**: Target <100ms image display, <50ms page transitions

## Feature Development Phases

### Current Phase: MVP (Phase 1)
Focus on basic image display and navigation:
- Single image file display (JPEG, PNG, WEBP)
- Basic window management
- Keyboard navigation (arrow keys)
- Folder-based sequential image viewing

### Important UI/UX Requirements

- **Window sizing**: Min 800x600, default 1200x900
- **Dark mode**: Full support required
- **Animations**: Keep minimal for performance
- **Controls**: Auto-hide when reading, show on hover/interaction

## Keyboard Shortcuts

| Function | Shortcut |
|----------|----------|
| Next Page | → / Space |
| Previous Page | ← |
| Toggle Double Page | D |
| Full Screen | Cmd+F |
| Show Gallery | Cmd+T |
| Show Library | Cmd+L |

## Testing Approach

When implementing features:
1. Create sample test data in Resources/SampleImages/
2. Test with various image formats and resolutions
3. Verify keyboard and trackpad navigation
4. Check memory usage stays under 500MB

## Dependencies to Consider

- **ZIPFoundation**: For ZIP/CBZ archive support
- **UnrarKit**: For RAR/CBR archive support

These should be added via Swift Package Manager when needed.

## Performance Requirements

- App launch: < 2 seconds
- Image display: < 100ms
- Page switch: < 50ms
- ZIP extraction: < 5s for 1000 pages
- Memory usage: < 500MB with cache

## Important Notes

- This is a personal-use application, not intended for App Store distribution
- Follow macOS Human Interface Guidelines strictly
- Prioritize reading experience over feature complexity
- "Tosho" branding should be consistent throughout the app
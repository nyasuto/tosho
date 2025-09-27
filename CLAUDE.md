# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Tosho (図書) is a native macOS manga viewer application built with SwiftUI. The project has completed Phase 1 MVP and is progressing through Phase 2 features, including archive support and advanced reading modes.

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
  - ContentView: Welcome screen and file/folder selection
  - ReaderView: Core manga reading interface with single/double page modes
  - WelcomeView: Initial landing page with drag-and-drop support

- **ViewModels/**: Business logic and state management
  - ReaderViewModel: Handles page navigation, zoom, single/double page modes, and memory-efficient caching

- **Models/**: Data structures
  - ToshoDocument: Unified document model for images, folders, and archives

- **Services/**: Core functionality providers
  - ArchiveExtractor: ZIP/CBZ extraction with memory optimization
  - FileLoader: Folder-based image file loading

### Key Technical Decisions

1. **Image Loading**: Implemented memory-efficient caching system with configurable cache size (default 5 images)
2. **Archive Handling**: Individual file extraction to minimize memory footprint, avoiding full extraction
3. **Double Page Mode**: Smart cover page detection with automatic single-page display for page 1
4. **Navigation**: Full keyboard support with D-key toggle for reading modes
5. **Performance**: Achieved smooth page transitions with background preloading

## Feature Development Phases

### ✅ Completed: Phase 1 MVP
Core functionality implemented:
- ✅ Single image file display (JPEG, PNG, WEBP, HEIC, TIFF, BMP, GIF, AVIF)
- ✅ Folder-based sequential image viewing with natural sorting
- ✅ Full keyboard navigation (arrow keys, space)
- ✅ Memory-efficient image caching and preloading
- ✅ Drag-and-drop file/folder support
- ✅ Welcome screen with file browser integration

### ✅ Completed: Archive Support (Issue #5)
- ✅ ZIP/CBZ archive extraction and viewing
- ✅ Memory-optimized individual file extraction
- ✅ Archive file listing and navigation

### ✅ Completed: Double Page Mode (Issue #7)
- ✅ Side-by-side page display for manga reading
- ✅ Smart cover page handling (single page for page 1)
- ✅ D-key toggle between single/double page modes
- ✅ Adaptive page navigation (1 or 2 pages at a time)

### 🚧 Current Phase: Phase 2 Advanced Features
In progress:
- [ ] Full-screen reading mode
- [ ] Zoom and pan improvements
- [ ] Reading progress tracking
- [ ] Additional gesture support

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

## Dependencies

### Currently Used
- **System unzip**: Leveraging macOS built-in unzip utility for ZIP/CBZ support
- **UniformTypeIdentifiers**: Modern file type handling for all supported formats

### Considered but Skipped
- **UnrarKit**: RAR/CBR support skipped due to licensing complexity (Issue #6)

No external dependencies currently required - leveraging macOS system utilities and frameworks.

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
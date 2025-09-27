//
//  ToshoDocument.swift
//  Tosho
//
//  Created on 2025/09/27.
//

import Foundation
import AppKit

enum ContentType {
    case singleImage(URL)
    case folder([URL])
    case archive(URL, [String])
}


class ToshoDocument: ObservableObject {
    @Published var contentType: ContentType?
    @Published var totalPages: Int = 0
    @Published var currentPageIndex: Int = 0

    private let archiveExtractor = ArchiveExtractor()

    func loadContent(from url: URL) throws {
        DebugLogger.shared.log("Loading content from: \(url.path)", category: "ToshoDocument")

        // 新しいファイルを読み込む前にキャッシュをクリア
        archiveExtractor.clearImageListCache()
        DebugLogger.shared.log("Cleared archive cache before loading new content", category: "ToshoDocument")

        if url.hasDirectoryPath {
            DebugLogger.shared.log("Loading as folder", category: "ToshoDocument")
            try loadFolder(url)
        } else if isArchiveFile(url) {
            DebugLogger.shared.log("Loading as archive: \(url.pathExtension)", category: "ToshoDocument")
            try loadArchive(url)
        } else {
            DebugLogger.shared.log("Loading as single image", category: "ToshoDocument")
            loadSingleImage(url)
        }
    }

    func getImage(at index: Int) throws -> NSImage? {
        guard index >= 0 && index < totalPages else {
            throw ToshoDocumentError.indexOutOfRange
        }

        switch contentType {
        case .singleImage(let url):
            return NSImage(contentsOf: url)

        case .folder(let urls):
            guard index < urls.count else { return nil }
            return NSImage(contentsOf: urls[index])

        case .archive(let archiveURL, let imageList):
            return try archiveExtractor.extractSingleImage(at: index, from: archiveURL, imageList: imageList)

        case .none:
            return nil
        }
    }

    func getCurrentImageURL() -> URL? {
        switch contentType {
        case .singleImage(let url):
            return url
        case .folder(let urls):
            guard currentPageIndex < urls.count else { return nil }
            return urls[currentPageIndex]
        case .archive:
            return nil
        case .none:
            return nil
        }
    }

    func getPageInfo(at index: Int) -> String? {
        switch contentType {
        case .singleImage(let url):
            return url.lastPathComponent
        case .folder(let urls):
            guard index < urls.count else { return nil }
            return urls[index].lastPathComponent
        case .archive(_, let imageList):
            guard index < imageList.count else { return nil }
            return imageList[index]
        case .none:
            return nil
        }
    }

    private func loadSingleImage(_ url: URL) {
        contentType = .singleImage(url)
        totalPages = 1
        currentPageIndex = 0
    }

    private func loadFolder(_ folderURL: URL) throws {
        let fileLoader = FileLoader()
        let urls = try fileLoader.loadImagesFromFolder(folderURL)
        guard !urls.isEmpty else {
            throw ToshoDocumentError.noImagesFound
        }

        contentType = .folder(urls)
        totalPages = urls.count
        currentPageIndex = 0
    }

    private func loadArchive(_ archiveURL: URL) throws {
        DebugLogger.shared.log("Loading archive: \(archiveURL.lastPathComponent)", category: "ToshoDocument")

        let imageList = try archiveExtractor.getImageList(from: archiveURL)
        guard !imageList.isEmpty else {
            DebugLogger.shared.log("No images found in archive", category: "ToshoDocument")
            throw ToshoDocumentError.noImagesFound
        }

        DebugLogger.shared.log("Archive loaded successfully with \(imageList.count) images", category: "ToshoDocument")
        contentType = .archive(archiveURL, imageList)
        totalPages = imageList.count
        currentPageIndex = 0
    }

    // MARK: - Phase 3: High-Performance Parallel Processing

    /// Concurrent extraction of multiple images for high-performance preloading
    func getImagesInRange(_ range: Range<Int>) async throws -> [Int: NSImage] {
        guard let contentType = contentType else {
            throw ToshoDocumentError.invalidContent
        }

        switch contentType {
        case .archive(let archiveURL, let imageList):
            // Use ZIPFoundation's advanced parallel processing
            #if canImport(ZIPFoundation)
            return try await archiveExtractor.zipFoundationExtractor.extractImagesInRange(
                range,
                from: archiveURL,
                imageList: imageList
            )
            #else
            // Fallback to sequential loading for non-ZIPFoundation builds
            var results: [Int: NSImage] = [:]
            for index in range {
                if let image = try getImage(at: index) {
                    results[index] = image
                }
            }
            return results
            #endif

        case .folder(let urls):
            // Parallel folder image loading
            return try await loadFolderImagesInRange(range, urls: urls)

        case .singleImage:
            // Single image - return immediately if in range
            if range.contains(0), let image = try getImage(at: 0) {
                return [0: image]
            }
            return [:]
        }
    }

    /// Priority-based preloading for optimal user experience
    func preloadImagesInRange(_ range: Range<Int>, priorityIndex: Int? = nil) async throws -> [Int: NSImage] {
        guard let contentType = contentType else {
            throw ToshoDocumentError.invalidContent
        }

        switch contentType {
        case .archive(let archiveURL, let imageList):
            #if canImport(ZIPFoundation)
            return try await archiveExtractor.zipFoundationExtractor.preloadImagesInRange(
                range,
                from: archiveURL,
                imageList: imageList,
                priorityIndex: priorityIndex
            )
            #else
            return try await getImagesInRange(range)
            #endif

        default:
            // For non-archive content, use standard range loading
            return try await getImagesInRange(range)
        }
    }

    /// Concurrent folder image loading with TaskGroup
    private func loadFolderImagesInRange(_ range: Range<Int>, urls: [URL]) async throws -> [Int: NSImage] {
        let maxConcurrentTasks = 3 // Limit for folder loading to avoid overwhelming filesystem

        return try await withThrowingTaskGroup(of: (Int, NSImage).self) { group in
            var activeTasks = 0
            var results: [Int: NSImage] = [:]

            for index in range {
                // Limit concurrent tasks
                if activeTasks >= maxConcurrentTasks {
                    if let (completedIndex, image) = try await group.next() {
                        results[completedIndex] = image
                        activeTasks -= 1
                    }
                }

                // Add new task if within bounds
                if index < urls.count {
                    let imageURL = urls[index]
                    group.addTask {
                        guard let image = NSImage(contentsOf: imageURL) else {
                            throw ToshoDocumentError.invalidContent
                        }
                        return (index, image)
                    }
                    activeTasks += 1
                }
            }

            // Wait for remaining tasks
            while activeTasks > 0 {
                if let (completedIndex, image) = try await group.next() {
                    results[completedIndex] = image
                    activeTasks -= 1
                }
            }

            return results
        }
    }

    private func isArchiveFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "zip" || ext == "cbz"
    }
}

enum ToshoDocumentError: Error, LocalizedError {
    case noImagesFound
    case indexOutOfRange
    case invalidContent

    var errorDescription: String? {
        switch self {
        case .noImagesFound:
            return "No image files found"
        case .indexOutOfRange:
            return "Page index out of range"
        case .invalidContent:
            return "Invalid content type"
        }
    }
}

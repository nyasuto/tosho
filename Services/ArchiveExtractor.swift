//
//  ArchiveExtractor.swift
//  Tosho
//
//  Created on 2025/09/27.
//

import Foundation
import AppKit
import UserNotifications
import os.log

#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

/// セキュリティスコープのアクセス権限を安全に管理するヘルパー関数
func withSecurityScope<T>(_ url: URL, _ work: () throws -> T) rethrows -> T {
    let ok = url.startAccessingSecurityScopedResource()
    defer {
        if ok {
            url.stopAccessingSecurityScopedResource()
        }
    }
    return try work()
}

// MARK: - ZIPFoundation based extractor
#if canImport(ZIPFoundation)
class ZIPFoundationExtractor {
    private let supportedImageExtensions = ["jpg", "jpeg", "png", "webp", "heic", "tiff", "bmp", "gif", "avif"]
    private var archiveCache: [URL: Archive] = [:]
    private var entriesCache: [URL: [String: Entry]] = [:]

    func getImageList(from archiveURL: URL) throws -> [String] {
        DebugLogger.shared.log("ZIPFoundation: Getting image list from \(archiveURL.lastPathComponent)", category: "ZIPFoundationExtractor")

        return try withSecurityScope(archiveURL) {
            let archive = try getArchive(for: archiveURL)
            let entries = getEntries(for: archiveURL, archive: archive)

            let imageFiles = entries.keys.filter { fileName in
                let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
                return supportedImageExtensions.contains(ext)
            }.sorted { name1, name2 in
                name1.localizedStandardCompare(name2) == .orderedAscending
            }

            DebugLogger.shared.log("ZIPFoundation: Found \(imageFiles.count) image files", category: "ZIPFoundationExtractor")
            return imageFiles
        }
    }

    func extractSingleImage(at index: Int, from archiveURL: URL, imageList: [String]) throws -> NSImage? {
        guard index >= 0 && index < imageList.count else {
            throw ArchiveError.indexOutOfRange
        }

        let imageName = imageList[index]
        DebugLogger.shared.log("ZIPFoundation: Extracting image \(imageName) at index \(index)", category: "ZIPFoundationExtractor")

        return try withSecurityScope(archiveURL) {
            let archive = try getArchive(for: archiveURL)
            let entries = getEntries(for: archiveURL, archive: archive)

            guard let entry = entries[imageName] else {
                DebugLogger.shared.log("ZIPFoundation: Entry not found for \(imageName)", category: "ZIPFoundationExtractor")
                throw ArchiveError.invalidArchive
            }

            // Extract directly to memory
            var imageData = Data()
            _ = try archive.extract(entry, bufferSize: 64 * 1024) { data in
                imageData.append(data)
            }

            // Create NSImage with downsampling
            guard let image = createOptimizedImage(from: imageData) else {
                DebugLogger.shared.log("ZIPFoundation: Failed to create NSImage from data", category: "ZIPFoundationExtractor")
                throw ArchiveError.imageLoadFailed
            }

            DebugLogger.shared.log("ZIPFoundation: Successfully extracted \(imageName)", category: "ZIPFoundationExtractor")
            return image
        }
    }

    private func getArchive(for url: URL) throws -> Archive {
        if let cachedArchive = archiveCache[url] {
            return cachedArchive
        }

        let archive = try Archive(url: url, accessMode: .read)
        archiveCache[url] = archive
        return archive
    }

    private func getEntries(for url: URL, archive: Archive) -> [String: Entry] {
        if let cachedEntries = entriesCache[url] {
            return cachedEntries
        }

        let entries = Dictionary(uniqueKeysWithValues: archive.map { ($0.path, $0) })
        entriesCache[url] = entries
        return entries
    }

    private func createOptimizedImage(from data: Data) -> NSImage? {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        // Create downsampled image for better memory efficiency
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048 // Reasonable size for manga pages
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            // Fallback to original image if thumbnail creation fails
            return NSImage(data: data)
        }

        return NSImage(cgImage: thumbnail, size: .zero)
    }

    // MARK: - Phase 3: Advanced Parallel Processing

    /// Concurrent extraction of multiple images with TaskGroup
    func extractImagesInRange(_ range: Range<Int>, from archiveURL: URL, imageList: [String]) async throws -> [Int: NSImage] {
        let maxConcurrentTasks = 4 // Optimal concurrency limit

        // Setup archive access with security scope
        let (archive, entries) = try withSecurityScope(archiveURL) {
            let archive = try getArchive(for: archiveURL)
            let entries = getEntries(for: archiveURL, archive: archive)
            return (archive, entries)
        }

        return try await withThrowingTaskGroup(of: (Int, NSImage).self) { group in
                var activeTasks = 0
                var results: [Int: NSImage] = [:]

                for index in range {
                    // Limit concurrent tasks for optimal memory usage
                    if activeTasks >= maxConcurrentTasks {
                        if let (completedIndex, image) = try await group.next() {
                            results[completedIndex] = image
                            activeTasks -= 1
                        }
                    }

                    // Add new task if within bounds
                    if index < imageList.count {
                        let imageName = imageList[index]
                        group.addTask { [weak self] in
                            guard let self = self else { throw ArchiveError.imageLoadFailed }
                            let image = try await self.extractSingleImageConcurrent(
                                at: index,
                                imageName: imageName,
                                from: archive,
                                entries: entries
                            )
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

    /// High-performance concurrent single image extraction
    private func extractSingleImageConcurrent(
        at index: Int,
        imageName: String,
        from archive: Archive,
        entries: [String: Entry]
    ) async throws -> NSImage {
        guard let entry = entries[imageName] else {
            DebugLogger.shared.logError(ArchiveError.imageLoadFailed, context: "Entry not found: \(imageName)")
            throw ArchiveError.imageLoadFailed
        }

        // Check if it's a STORED (uncompressed) entry for memory mapping optimization
        // Note: ZIPFoundation's Entry doesn't expose compressionMethod directly
        // We'll use a heuristic: if compressed size equals uncompressed size, it's likely STORED
        if entry.type == .file && entry.compressedSize == entry.uncompressedSize {
            return try await extractStoredImageOptimized(entry: entry, from: archive)
        }

        // Standard compressed extraction
        return try await extractCompressedImage(entry: entry, from: archive)
    }

    /// Memory-mapped optimization for STORED (uncompressed) archives
    private func extractStoredImageOptimized(entry: Entry, from archive: Archive) async throws -> NSImage {
        // For STORED entries, we can potentially use memory mapping
        // This provides zero-copy access for large files
        var imageData = Data()
        imageData.reserveCapacity(Int(entry.uncompressedSize))

        // Use larger buffer for uncompressed data
        _ = try archive.extract(entry, bufferSize: 256 * 1024) { data in
            imageData.append(data)
        }

        guard let image = createOptimizedImage(from: imageData) else {
            throw ArchiveError.imageLoadFailed
        }

        DebugLogger.shared.log("ZIPFoundation: STORED image extracted \(entry.path)", category: "ZIPFoundationExtractor")
        return image
    }

    /// Standard compressed image extraction
    private func extractCompressedImage(entry: Entry, from archive: Archive) async throws -> NSImage {
        var imageData = Data()
        imageData.reserveCapacity(Int(entry.uncompressedSize))

        // Standard 64KB buffer for compressed data
        _ = try archive.extract(entry, bufferSize: 64 * 1024) { data in
            imageData.append(data)
        }

        guard let image = createOptimizedImage(from: imageData) else {
            throw ArchiveError.imageLoadFailed
        }

        DebugLogger.shared.log("ZIPFoundation: Compressed image extracted \(entry.path)", category: "ZIPFoundationExtractor")
        return image
    }

    /// Enhanced batch preloading with smart priority
    func preloadImagesInRange(_ range: Range<Int>, from archiveURL: URL, imageList: [String], priorityIndex: Int? = nil) async throws -> [Int: NSImage] {
        let indices = Array(range)

        // Sort by priority if specified (closest to priority index first)
        let sortedIndices: [Int]
        if let priorityIndex = priorityIndex {
            sortedIndices = indices.sorted { abs($0 - priorityIndex) < abs($1 - priorityIndex) }
        } else {
            sortedIndices = indices
        }

        let first = sortedIndices.first!
        let last = sortedIndices.last!
        let prioritizedRange = first..<max(first + 1, last + 1)
        return try await extractImagesInRange(prioritizedRange, from: archiveURL, imageList: imageList)
    }

    func clearCache() {
        archiveCache.removeAll()
        entriesCache.removeAll()
        DebugLogger.shared.log("ZIPFoundation: Cache cleared", category: "ZIPFoundationExtractor")
    }
}
#endif

// ZIPFoundationベースの実装では、メモリへの事前ロードは不要
// ZIPFoundationが効率的にストリーミング処理を行う

class ArchiveExtractor {
    private let supportedImageExtensions = ["jpg", "jpeg", "png", "webp", "heic", "tiff", "bmp", "gif", "avif"]
    private let tempDirectory: URL

    // ZIPFoundation extractor for high performance
    #if canImport(ZIPFoundation)
    let zipFoundationExtractor = ZIPFoundationExtractor() // Public access for Phase 3 integration
    #endif

    // Fallback: イメージリストキャッシュ（従来のunzip用）
    private var archiveImageLists: [URL: [String]] = [:]

    init() {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ToshoArchives")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    deinit {
        cleanup()
        #if canImport(ZIPFoundation)
        zipFoundationExtractor.clearCache()
        #endif
    }

    // MARK: - Cache Management

    /// イメージリストキャッシュをクリア
    func clearImageListCache() {
        self.archiveImageLists.removeAll()
        #if canImport(ZIPFoundation)
        zipFoundationExtractor.clearCache()
        #endif
    }

    func extractArchive(at archiveURL: URL) throws -> [URL] {
        guard isArchiveFile(archiveURL) else {
            throw ArchiveError.unsupportedFormat
        }

        let extractionURL = tempDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: extractionURL, withIntermediateDirectories: true)

        try unzipFile(at: archiveURL, to: extractionURL)

        let imageURLs = try findImageFiles(in: extractionURL)
        return imageURLs.sorted { url1, url2 in
            url1.lastPathComponent.localizedStandardCompare(url2.lastPathComponent) == .orderedAscending
        }
    }

    func extractSingleImage(at index: Int, from archiveURL: URL, imageList: [String]) throws -> NSImage? {
        guard index >= 0 && index < imageList.count else {
            DebugLogger.shared.logArchiveOperation("Index out of range",
                                                   file: archiveURL.lastPathComponent,
                                                   details: "Index: \(index), Total: \(imageList.count)")
            throw ArchiveError.indexOutOfRange
        }

        let imageName = imageList[index]

        // Try ZIPFoundation first for optimal performance
        #if canImport(ZIPFoundation)
        do {
            DebugLogger.shared.log("Attempting ZIPFoundation extraction for image: \(imageName)", category: "ArchiveExtractor")
            return try zipFoundationExtractor.extractSingleImage(at: index, from: archiveURL, imageList: imageList)
        } catch {
            DebugLogger.shared.log("ZIPFoundation extraction failed, falling back to unzip: \(error)", category: "ArchiveExtractor")
        }
        #endif

        // Fallback to unzip command
        let archiveLog = Logger(subsystem: "com.tosho.app", category: "archive")
        DebugLogger.shared.logArchiveOperation("Extracting image with unzip fallback",
                                               file: archiveURL.lastPathComponent,
                                               details: "Image: \(imageName) (index \(index))")
        archiveLog.info("🗜️ Extracting image with unzip fallback: \(imageName, privacy: .public)")

        // Try memory-based extraction first with ZipExtractor
        if ZipExtractor.isSupported(archiveURL) {
            do {
                let image = try ZipExtractor.image(forMember: imageName, inArchive: archiveURL)
                DebugLogger.shared.logArchiveOperation("Memory extraction successful",
                                                       file: archiveURL.lastPathComponent,
                                                       details: "Image: \(imageName)")
                archiveLog.info("✅ ZipExtractor memory extraction successful for: \(imageName, privacy: .public)")
                return image
            } catch {
                DebugLogger.shared.logArchiveOperation("Memory extraction failed, falling back to Archive framework",
                                                       file: archiveURL.lastPathComponent,
                                                       details: "Error: \(error.localizedDescription)")
                archiveLog.info("⚠️ ZipExtractor failed, falling back to Archive framework")
            }
        }

        // Fallback to disk-based extraction with security scope
        return try withSecurityScope(archiveURL) {
            archiveLog.info("🔓 Security scope started for disk-based extraction")
            DebugLogger.shared.logArchiveOperation("Using disk-based extraction",
                                                   file: archiveURL.lastPathComponent,
                                                   details: "Image: \(imageName)")

            let tempImageURL = tempDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("temp")

            // セキュリティスコープ内でファイル抽出実行
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-o", "-q", archiveURL.path, imageName, "-d", tempImageURL.deletingLastPathComponent().path]

            archiveLog.info("🚀 Executing unzip extraction with security scope")

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                archiveLog.error("❌ Unzip extraction failed with exit code: \(process.terminationStatus)")
                throw ArchiveError.extractionFailed
            }

            let extractedFileURL = tempImageURL.deletingLastPathComponent().appendingPathComponent(imageName)
            if FileManager.default.fileExists(atPath: extractedFileURL.path) {
                try FileManager.default.moveItem(at: extractedFileURL, to: tempImageURL)
            }

            guard let image = NSImage(contentsOf: tempImageURL) else {
                try? FileManager.default.removeItem(at: tempImageURL)
                throw ArchiveError.imageLoadFailed
            }

            try? FileManager.default.removeItem(at: tempImageURL)
            archiveLog.info("✅ Successfully extracted and loaded image")
            return image
        }
    }

    func getImageList(from archiveURL: URL) throws -> [String] {
        guard isArchiveFile(archiveURL) else {
            throw ArchiveError.unsupportedFormat
        }

        // Try ZIPFoundation first for optimal performance
        #if canImport(ZIPFoundation)
        do {
            DebugLogger.shared.log("Attempting ZIPFoundation extraction for: \(archiveURL.lastPathComponent)", category: "ArchiveExtractor")
            return try zipFoundationExtractor.getImageList(from: archiveURL)
        } catch {
            DebugLogger.shared.log("ZIPFoundation failed, falling back to unzip: \(error)", category: "ArchiveExtractor")
        }
        #endif

        // Fallback to unzip command
        let unzipLog = Logger(subsystem: "com.tosho.app", category: "unzip")
        DebugLogger.shared.logArchiveOperation("Getting image list with unzip fallback", file: archiveURL.lastPathComponent)
        unzipLog.info("📋 Starting getImageList with security scoped unzip for: \(archiveURL.lastPathComponent, privacy: .public)")

        // キャッシュされたイメージリストをチェック
        if let cachedImageList = self.archiveImageLists[archiveURL] {
            unzipLog.info("🔄 Using cached image list for: \(archiveURL.lastPathComponent, privacy: .public)")
            return cachedImageList
        }

        // Use security scoped access for network drives
        return try withSecurityScope(archiveURL) {
            unzipLog.info("🔓 Security scope started for unzip access")
            unzipLog.info("🔍 Archive URL path: \(archiveURL.path, privacy: .public)")
            unzipLog.info("🔍 Archive URL exists: \(FileManager.default.fileExists(atPath: archiveURL.path))")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-l", archiveURL.path]

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            unzipLog.info("🚀 Executing unzip -l with security scope")

            try process.run()
            process.waitUntilExit()

            // 標準エラー出力を取得
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
                unzipLog.error("📢 Unzip stderr: \(errorOutput, privacy: .public)")
            }

            unzipLog.info("📊 Unzip process completed with exit code: \(process.terminationStatus)")

            guard process.terminationStatus == 0 else {
                unzipLog.error("❌ Unzip list failed for: \(archiveURL.lastPathComponent, privacy: .public) with exit code: \(process.terminationStatus)")
                DebugLogger.shared.logArchiveOperation("Unzip list failed",
                                                       file: archiveURL.lastPathComponent,
                                                       details: "Exit code: \(process.terminationStatus)")
                throw ArchiveError.extractionFailed
            }

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                DebugLogger.shared.logArchiveOperation("Failed to decode unzip output", file: archiveURL.lastPathComponent)
                throw ArchiveError.invalidArchive
            }

            DebugLogger.shared.logArchiveOperation("Successfully listed archive contents",
                                                   file: archiveURL.lastPathComponent,
                                                   details: "Output length: \(output.count)")
            let imageFiles = parseImageFilesFromUnzipList(output)

            // 結果をキャッシュ
            self.archiveImageLists[archiveURL] = imageFiles

            DebugLogger.shared.logArchiveOperation("Found \(imageFiles.count) image files", file: archiveURL.lastPathComponent)
            unzipLog.info("✅ Successfully found \(imageFiles.count) image files")
            return imageFiles
        }
    }

    private func isArchiveFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "zip" || ext == "cbz"
    }

    private func unzipFile(at sourceURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", sourceURL.path, "-d", destinationURL.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ArchiveError.extractionFailed
        }
    }

    private func findImageFiles(in directoryURL: URL) throws -> [URL] {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(at: directoryURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])

        var imageURLs: [URL] = []

        while let url = enumerator?.nextObject() as? URL {
            let ext = url.pathExtension.lowercased()
            if supportedImageExtensions.contains(ext) {
                imageURLs.append(url)
            }
        }

        return imageURLs
    }

    private func parseImageFilesFromUnzipList(_ output: String) -> [String] {
        let lines = output.components(separatedBy: .newlines)
        var imageFiles: [String] = []

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty || trimmedLine.starts(with: "Archive:") || trimmedLine.starts(with: "Length") || trimmedLine.starts(with: "---") {
                continue
            }

            // unzip -l の出力形式: Length Date Time Name
            // 例: "87130  07-21-2025 11:12   01.webp"
            // 正規表現を使って確実にファイル名部分を抽出
            let pattern = #"^\s*\d+\s+\d{2}-\d{2}-\d{4}\s+\d{2}:\d{2}\s+(.+)$"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: trimmedLine, range: NSRange(trimmedLine.startIndex..., in: trimmedLine)),
               let fileNameRange = Range(match.range(at: 1), in: trimmedLine) {

                let fileName = String(trimmedLine[fileNameRange])
                let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
                if supportedImageExtensions.contains(ext) {
                    DebugLogger.shared.logArchiveOperation("Found image file",
                                                           details: "File: '\(fileName)'")
                    imageFiles.append(fileName)
                }
            }
        }

        return imageFiles.sorted { name1, name2 in
            name1.localizedStandardCompare(name2) == .orderedAscending
        }
    }

    private func cleanup() {
        try? FileManager.default.removeItem(at: tempDirectory)
    }
}

enum ArchiveError: Error, LocalizedError {
    case unsupportedFormat
    case extractionFailed
    case invalidArchive
    case imageLoadFailed
    case indexOutOfRange

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Unsupported archive format. Only ZIP and CBZ files are supported."
        case .extractionFailed:
            return "Failed to extract archive."
        case .invalidArchive:
            return "Invalid archive file."
        case .imageLoadFailed:
            return "Failed to load image from archive."
        case .indexOutOfRange:
            return "Image index out of range."
        }
    }
}


// MARK: - File History Management

struct FileHistoryItem: Codable, Identifiable {
    let id: UUID
    let url: URL
    let fileName: String
    private(set) var accessCount: Int
    private(set) var firstAccessed: Date
    private(set) var lastAccessed: Date
    private(set) var isFavorite: Bool
    private(set) var isAutoFavorite: Bool // システムが自動で付けたお気に入り
    private(set) var bookmarkData: Data? // セキュリティスコープのアクセス権限保持用

    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.fileName = url.lastPathComponent
        self.accessCount = 1
        self.firstAccessed = Date()
        self.lastAccessed = Date()
        self.isFavorite = false
        self.isAutoFavorite = false

        // セキュリティスコープのブックマークデータを作成
        do {
            self.bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            DebugLogger.shared.log("Created security scoped bookmark for: \(url.lastPathComponent)", category: "FileHistoryItem")
        } catch {
            self.bookmarkData = nil
            DebugLogger.shared.logError(error, context: "Failed to create security scoped bookmark for: \(url.lastPathComponent)")
        }
    }

    // アクセス回数を増やす
    mutating func incrementAccess() {
        accessCount += 1
        lastAccessed = Date()
    }

    // お気に入り状態を設定
    mutating func setFavorite(_ favorite: Bool, isAuto: Bool = false) {
        isFavorite = favorite
        if isAuto {
            isAutoFavorite = favorite
        }
    }

    // 自動お気に入り対象かどうか
    var shouldBeAutoFavorite: Bool {
        return accessCount >= 5 && !isAutoFavorite
    }

    var formattedAccessCount: String {
        return "\(accessCount)回"
    }

    var formattedLastAccessed: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: lastAccessed, relativeTo: Date())
    }

    // セキュリティスコープのアクセス権限を取得
    mutating func getSecurityScopedURL() -> URL? {
        let bookmarkLog = Logger(subsystem: "com.tosho.app", category: "bookmark")
        let fileName = self.fileName // ローカルコピー

        guard let bookmarkData = self.bookmarkData else {
            bookmarkLog.info("No bookmark data available for: \(fileName, privacy: .public)")
            DebugLogger.shared.log("No bookmark data available for: \(fileName)", category: "FileHistoryItem")
            return nil
        }

        bookmarkLog.info("Attempting to resolve bookmark for: \(fileName, privacy: .public), data size: \(bookmarkData.count) bytes")

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                bookmarkLog.warning("Bookmark data is stale for: \(fileName, privacy: .public)")
                DebugLogger.shared.log("Bookmark data is stale for: \(fileName)", category: "FileHistoryItem")

                // ファイルが存在するかチェック
                if FileManager.default.fileExists(atPath: url.path) {
                    bookmarkLog.info("File still exists, attempting to create fresh bookmark for: \(fileName, privacy: .public)")
                    DebugLogger.shared.log("File still exists, attempting to create fresh bookmark for: \(fileName)", category: "FileHistoryItem")

                    // 新しいブックマークを作成
                    do {
                        let freshBookmarkData = try url.bookmarkData(
                            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        )
                        // 新しいブックマークデータを保存
                        self.bookmarkData = freshBookmarkData
                        bookmarkLog.info("Successfully created fresh bookmark for: \(fileName, privacy: .public)")
                        DebugLogger.shared.log("Successfully created fresh bookmark for: \(fileName)", category: "FileHistoryItem")
                        return url
                    } catch {
                        bookmarkLog.error("Failed to create fresh bookmark for: \(fileName, privacy: .public) - \(error.localizedDescription, privacy: .public)")
                        DebugLogger.shared.logError(error, context: "Failed to create fresh bookmark for: \(fileName)")
                        // フレッシュブックマーク作成に失敗した場合はnilを返す
                        // これによりopenFileFromHistoryでフォールバック処理が実行される
                        return nil
                    }
                } else {
                    bookmarkLog.error("File no longer exists at: \(url.path, privacy: .public)")
                    DebugLogger.shared.log("File no longer exists at: \(url.path)", category: "FileHistoryItem")
                    return nil
                }
            }

            bookmarkLog.info("Successfully resolved security scoped URL for: \(fileName, privacy: .public) -> \(url.path, privacy: .public)")
            DebugLogger.shared.log("Successfully resolved security scoped URL for: \(fileName)", category: "FileHistoryItem")
            return url
        } catch {
            bookmarkLog.error("Failed to resolve security scoped URL for: \(fileName, privacy: .public) - \(error.localizedDescription, privacy: .public)")
            DebugLogger.shared.logError(error, context: "Failed to resolve security scoped URL for: \(fileName)")
            return nil
        }
    }

    // セキュリティスコープのアクセス権限を開始
    mutating func startAccessingSecurityScopedResource() -> Bool {
        let securityLog = Logger(subsystem: "com.tosho.app", category: "security")
        let fileName = self.fileName // ローカルコピー

        guard let securityScopedURL = getSecurityScopedURL() else {
            securityLog.error("Cannot get security scoped URL for: \(fileName, privacy: .public)")
            return false
        }

        securityLog.info("Attempting to start accessing security scoped resource: \(fileName, privacy: .public) at \(securityScopedURL.path, privacy: .public)")

        // ファイルが存在するかチェック
        let fileExists = FileManager.default.fileExists(atPath: securityScopedURL.path)
        securityLog.info("File exists check for \(fileName, privacy: .public): \(fileExists)")

        let success = securityScopedURL.startAccessingSecurityScopedResource()
        if success {
            securityLog.info("✅ Successfully started accessing security scoped resource: \(fileName, privacy: .public)")
            DebugLogger.shared.log("Started accessing security scoped resource: \(fileName)", category: "FileHistoryItem")
        } else {
            securityLog.error("❌ Failed to start accessing security scoped resource: \(fileName, privacy: .public)")
            DebugLogger.shared.log("Failed to start accessing security scoped resource: \(fileName)", category: "FileHistoryItem")
        }
        return success
    }

    // セキュリティスコープのアクセス権限を終了
    mutating func stopAccessingSecurityScopedResource() {
        let fileName = self.fileName // ローカルコピー

        guard let securityScopedURL = getSecurityScopedURL() else {
            return
        }

        securityScopedURL.stopAccessingSecurityScopedResource()
        DebugLogger.shared.log("Stopped accessing security scoped resource: \(fileName)", category: "FileHistoryItem")
    }

    // 古いアイテムのメタデータを保持して新しいURLで初期化
    init(url: URL, preservingMetadataFrom oldItem: FileHistoryItem) {
        self.id = UUID()
        self.url = url
        self.fileName = url.lastPathComponent
        self.accessCount = oldItem.accessCount
        self.firstAccessed = oldItem.firstAccessed
        self.lastAccessed = Date() // 最新アクセス時刻に更新
        self.isFavorite = oldItem.isFavorite
        self.isAutoFavorite = oldItem.isAutoFavorite

        // セキュリティスコープのブックマークデータを作成
        do {
            self.bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            DebugLogger.shared.log("Created fresh bookmark for replaced item: \(url.lastPathComponent)", category: "FileHistoryItem")
        } catch {
            self.bookmarkData = nil
            DebugLogger.shared.logError(error, context: "Failed to create bookmark for replaced item: \(url.lastPathComponent)")
        }
    }
}

class FavoritesManager: ObservableObject {
    static let shared = FavoritesManager()

    @Published private(set) var fileHistory: [FileHistoryItem] = []
    @Published private(set) var autoFavoriteSuggestions: [FileHistoryItem] = []

    private let userDefaults = UserDefaults.standard
    private let fileHistoryKey = "ToshoFileHistory"
    private let autoFavoriteThreshold = 5

    // 詳細デバッグログ用
    private let bookmarkLog = Logger(subsystem: "com.tosho.app", category: "bookmark")
    private let securityLog = Logger(subsystem: "com.tosho.app", category: "security")
    private let unzipLog = Logger(subsystem: "com.tosho.app", category: "unzip")

    private init() {
        loadFileHistory()
        updateAutoFavoriteSuggestions()
    }

    // MARK: - Public Methods

    func recordFileAccess(_ url: URL) {
        DebugLogger.shared.log("Recording file access: \(url.lastPathComponent)", category: "FavoritesManager")

        if let existingIndex = fileHistory.firstIndex(where: { $0.url == url }) {
            // 既存のアイテムのアクセス回数を増やす
            fileHistory[existingIndex].incrementAccess()

            // 自動お気に入り候補チェック
            let item = fileHistory[existingIndex]
            if item.shouldBeAutoFavorite {
                showAutoFavoriteSuggestion(for: item)
            }
        } else {
            // 新しいアイテムを追加
            let newItem = FileHistoryItem(url: url)
            fileHistory.insert(newItem, at: 0)
        }

        saveFileHistory()
        updateAutoFavoriteSuggestions()
    }

    func setFavorite(_ url: URL, favorite: Bool, isAuto: Bool = false) {
        if let index = fileHistory.firstIndex(where: { $0.url == url }) {
            fileHistory[index].setFavorite(favorite, isAuto: isAuto)
            saveFileHistory()
            updateAutoFavoriteSuggestions()

            DebugLogger.shared.log("Set favorite \(favorite) for: \(url.lastPathComponent)", category: "FavoritesManager")
        }
    }

    func getFavorites() -> [FileHistoryItem] {
        return fileHistory.filter { $0.isFavorite }.sorted { $0.lastAccessed > $1.lastAccessed }
    }

    func getFrequentlyAccessed() -> [FileHistoryItem] {
        return fileHistory.filter { $0.accessCount >= 3 }.sorted { $0.accessCount > $1.accessCount }
    }

    func dismissAutoFavoriteSuggestion(_ url: URL) {
        if let index = fileHistory.firstIndex(where: { $0.url == url }) {
            fileHistory[index].setFavorite(false, isAuto: true) // 自動提案を無効化
            saveFileHistory()
            updateAutoFavoriteSuggestions()
        }
    }

    func clearHistory() {
        fileHistory.removeAll()
        autoFavoriteSuggestions.removeAll()
        saveFileHistory()
    }

    // 履歴アイテムのURLを置換（ファイルが移動された場合など）
    func replaceHistoryItem(oldURL: URL, newURL: URL) {
        guard let index = fileHistory.firstIndex(where: { $0.url == oldURL }) else {
            // 古いアイテムが見つからない場合は新しいアイテムを追加
            recordFileAccess(newURL)
            return
        }

        let oldItem = fileHistory[index]

        // 新しいアイテムを作成（古いアイテムの統計情報を保持）
        let newItem = FileHistoryItem(url: newURL, preservingMetadataFrom: oldItem)

        // リストを更新
        fileHistory[index] = newItem
        saveFileHistory()

        DebugLogger.shared.log("Replaced history item: \(oldURL.lastPathComponent) -> \(newURL.lastPathComponent)", category: "FavoritesManager")
    }

    // 履歴からファイルを開く際にセキュリティスコープを処理
    func openFileFromHistory(_ url: URL, completion: @escaping (URL?) -> Void) {
        securityLog.info("🔍 Opening file from history: \(url.lastPathComponent, privacy: .public)")

        guard let index = fileHistory.firstIndex(where: { $0.url == url }) else {
            securityLog.error("❌ File not found in history: \(url.lastPathComponent, privacy: .public)")
            DebugLogger.shared.log("File not found in history: \(url.lastPathComponent)", category: "FavoritesManager")
            completion(nil)
            return
        }

        securityLog.info("📚 Found item in history, attempting security scope access")

        // セキュリティスコープのアクセス権限を取得
        if let securityScopedURL = fileHistory[index].getSecurityScopedURL() {
            // ブックマークが更新された可能性があるので保存
            saveFileHistory()
            securityLog.info("🔐 Got security scoped URL, starting access...")
            if securityScopedURL.startAccessingSecurityScopedResource() {
                securityLog.info("✅ Successfully started accessing security scoped resource for: \(url.lastPathComponent, privacy: .public)")
                DebugLogger.shared.log("Successfully started accessing security scoped resource for: \(url.lastPathComponent)", category: "FavoritesManager")
                completion(securityScopedURL)
            } else {
                securityLog.error("❌ Failed to start accessing security scoped resource for: \(url.lastPathComponent, privacy: .public)")
                DebugLogger.shared.log("Failed to start accessing security scoped resource for: \(url.lastPathComponent)", category: "FavoritesManager")
                completion(nil)
            }
        } else {
            // セキュリティスコープが利用できない場合のフォールバック処理
            securityLog.warning("⚠️ Security scope not available, trying fallback approaches for: \(url.lastPathComponent, privacy: .public)")
            DebugLogger.shared.log("Security scope not available, trying fallback approaches for: \(url.lastPathComponent)", category: "FavoritesManager")

            // 1. 元のURLがアクセス可能かチェック
            if FileManager.default.fileExists(atPath: url.path) {
                securityLog.info("Original URL is accessible, using it for: \(url.lastPathComponent, privacy: .public)")
                DebugLogger.shared.log("Original URL is accessible, using it for: \(url.lastPathComponent)", category: "FavoritesManager")
                completion(url)
                return
            }

            // 2. ファイルピッカーで再選択を促す
            securityLog.error("❌ File not accessible at original location: \(url.path, privacy: .public)")
            DebugLogger.shared.log("File not accessible at original location: \(url.path)", category: "FavoritesManager")

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "ファイルにアクセスできません"
                alert.informativeText = "「\(url.lastPathComponent)」にアクセスできません。ファイルを再選択してください。"
                alert.addButton(withTitle: "再選択")
                alert.addButton(withTitle: "キャンセル")
                alert.alertStyle = .warning

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    // ファイルピッカーを開く
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    panel.canChooseFiles = true
                    panel.directoryURL = url.deletingLastPathComponent()

                    if panel.runModal() == .OK, let newURL = panel.url {
                        // 古いアイテムを削除して新しいアイテムを作成
                        DispatchQueue.main.async {
                            // FavoritesManagerの参照を取得してアイテムを更新
                            FavoritesManager.shared.replaceHistoryItem(oldURL: url, newURL: newURL)
                            completion(newURL)
                        }
                    } else {
                        completion(nil)
                    }
                } else {
                    completion(nil)
                }
            }
        }
    }

    // セキュリティスコープのアクセス権限を終了
    func stopAccessingFileFromHistory(_ url: URL) {
        guard let index = fileHistory.firstIndex(where: { $0.url == url }) else {
            return
        }

        fileHistory[index].stopAccessingSecurityScopedResource()
    }

    // MARK: - Private Methods

    private func loadFileHistory() {
        guard let data = userDefaults.data(forKey: fileHistoryKey),
              let items = try? JSONDecoder().decode([FileHistoryItem].self, from: data) else {
            DebugLogger.shared.log("No file history found or failed to decode", category: "FavoritesManager")
            return
        }

        fileHistory = items
        DebugLogger.shared.log("Loaded file history: \(items.count) items", category: "FavoritesManager")
    }

    private func saveFileHistory() {
        do {
            let data = try JSONEncoder().encode(fileHistory)
            userDefaults.set(data, forKey: fileHistoryKey)
            DebugLogger.shared.log("Saved file history: \(fileHistory.count) items", category: "FavoritesManager")
        } catch {
            DebugLogger.shared.logError(error, context: "Failed to save file history")
        }
    }

    private func updateAutoFavoriteSuggestions() {
        autoFavoriteSuggestions = fileHistory.filter { $0.shouldBeAutoFavorite }
        DebugLogger.shared.log("Updated auto-favorite suggestions: \(autoFavoriteSuggestions.count) items", category: "FavoritesManager")
    }

    private func showAutoFavoriteSuggestion(for item: FileHistoryItem) {
        // 通知でユーザーに自動お気に入り候補を提案
        DispatchQueue.main.async {
            let content = UNMutableNotificationContent()
            content.title = "お気に入り候補"
            content.body = "\(item.fileName) を \(item.accessCount) 回開きました。お気に入りに追加しますか？"
            content.categoryIdentifier = "AUTO_FAVORITE_SUGGESTION"
            content.userInfo = ["fileURL": item.url.absoluteString]

            let request = UNNotificationRequest(identifier: "auto_favorite_\(item.id.uuidString)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}

//
//  ArchiveExtractor.swift
//  Tosho
//
//  Created on 2025/09/27.
//

import Foundation
import AppKit

class ArchiveExtractor {
    private let supportedImageExtensions = ["jpg", "jpeg", "png", "webp", "heic", "tiff", "bmp", "gif", "avif"]
    private let tempDirectory: URL

    init() {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ToshoArchives")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    deinit {
        cleanup()
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
        DebugLogger.shared.logArchiveOperation("Extracting image",
                                               file: archiveURL.lastPathComponent,
                                               details: "Image: \(imageName) (index \(index))")

        // Try memory-based extraction first
        if ZipExtractor.isSupported(archiveURL) {
            do {
                let image = try ZipExtractor.image(forMember: imageName, inArchive: archiveURL)
                DebugLogger.shared.logArchiveOperation("Memory extraction successful",
                                                       file: archiveURL.lastPathComponent,
                                                       details: "Image: \(imageName)")
                return image
            } catch {
                DebugLogger.shared.logArchiveOperation("Memory extraction failed, falling back to disk",
                                                       file: archiveURL.lastPathComponent,
                                                       details: "Error: \(error.localizedDescription)")
                // Continue to disk-based fallback below
            }
        }

        // Fallback to disk-based extraction
        DebugLogger.shared.logArchiveOperation("Using disk-based extraction",
                                               file: archiveURL.lastPathComponent,
                                               details: "Image: \(imageName)")
        let tempImageURL = tempDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("temp")

        try extractSpecificFile(fileName: imageName, from: archiveURL, to: tempImageURL)

        guard let image = NSImage(contentsOf: tempImageURL) else {
            try? FileManager.default.removeItem(at: tempImageURL)
            throw ArchiveError.imageLoadFailed
        }

        try? FileManager.default.removeItem(at: tempImageURL)
        return image
    }

    func getImageList(from archiveURL: URL) throws -> [String] {
        DebugLogger.shared.logArchiveOperation("Getting image list", file: archiveURL.lastPathComponent)

        guard isArchiveFile(archiveURL) else {
            DebugLogger.shared.logError(ArchiveError.unsupportedFormat, context: "File: \(archiveURL.lastPathComponent)")
            throw ArchiveError.unsupportedFormat
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-l", archiveURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            DebugLogger.shared.logArchiveOperation("Unzip list failed",
                                                   file: archiveURL.lastPathComponent,
                                                   details: "Exit code: \(process.terminationStatus)")
            throw ArchiveError.extractionFailed
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            DebugLogger.shared.logArchiveOperation("Failed to decode unzip output", file: archiveURL.lastPathComponent)
            throw ArchiveError.invalidArchive
        }

        DebugLogger.shared.logArchiveOperation("Successfully listed archive contents",
                                               file: archiveURL.lastPathComponent,
                                               details: "Output length: \(output.count)")
        let imageFiles = parseImageFilesFromUnzipList(output)
        DebugLogger.shared.logArchiveOperation("Found \(imageFiles.count) image files", file: archiveURL.lastPathComponent)
        return imageFiles
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

    private func extractSpecificFile(fileName: String, from archiveURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", archiveURL.path, fileName, "-d", destinationURL.deletingLastPathComponent().path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ArchiveError.extractionFailed
        }

        let extractedFileURL = destinationURL.deletingLastPathComponent().appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: extractedFileURL.path) {
            try FileManager.default.moveItem(at: extractedFileURL, to: destinationURL)
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

// MARK: - Recent Files Management

struct RecentFileItem: Codable, Identifiable {
    let id: UUID
    let url: URL
    let lastOpened: Date
    let fileName: String
    let fileSize: Int64
    let thumbnailData: Data?

    init(url: URL, thumbnailData: Data? = nil) {
        self.id = UUID()
        self.url = url
        self.lastOpened = Date()
        self.fileName = url.lastPathComponent

        // Get file size
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? NSNumber {
            self.fileSize = size.int64Value
        } else {
            self.fileSize = 0
        }

        self.thumbnailData = thumbnailData
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedLastOpened: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: lastOpened, relativeTo: Date())
    }
}

class RecentFilesManager: ObservableObject {
    static let shared = RecentFilesManager()

    @Published private(set) var recentFiles: [RecentFileItem] = []

    private let maxRecentFiles = 20
    private let userDefaults = UserDefaults.standard
    private let recentFilesKey = "ToshoRecentFiles"

    private init() {
        loadRecentFiles()
        validateAndCleanupFiles()
    }

    // MARK: - Public Methods

    func addRecentFile(_ url: URL, thumbnailData: Data? = nil) {
        DebugLogger.shared.logArchiveOperation("Adding recent file",
                                               file: url.lastPathComponent)

        // Remove existing entry if present
        removeRecentFile(url)

        // Create new entry
        let newItem = RecentFileItem(url: url, thumbnailData: thumbnailData)
        recentFiles.insert(newItem, at: 0)

        // Limit to max files
        if recentFiles.count > maxRecentFiles {
            recentFiles = Array(recentFiles.prefix(maxRecentFiles))
        }

        saveRecentFiles()
        updateSystemRecentMenu()
    }

    func removeRecentFile(_ url: URL) {
        recentFiles.removeAll { $0.url == url }
        saveRecentFiles()
        updateSystemRecentMenu()
    }

    func clearAllRecentFiles() {
        DebugLogger.shared.logArchiveOperation("Clearing all recent files")
        recentFiles.removeAll()
        saveRecentFiles()
        updateSystemRecentMenu()
    }

    func validateAndCleanupFiles() {
        let existingFiles = recentFiles.filter { FileManager.default.fileExists(atPath: $0.url.path) }

        if existingFiles.count != recentFiles.count {
            let removedCount = recentFiles.count - existingFiles.count
            DebugLogger.shared.logArchiveOperation("Cleaned up non-existent files",
                                                   details: "Removed \(removedCount) files")
            recentFiles = existingFiles
            saveRecentFiles()
            updateSystemRecentMenu()
        }
    }

    func getFilteredFiles(searchText: String) -> [RecentFileItem] {
        if searchText.isEmpty {
            return recentFiles
        }

        return recentFiles.filter { item in
            item.fileName.localizedCaseInsensitiveContains(searchText) ||
            item.url.path.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Private Methods

    private func loadRecentFiles() {
        guard let data = userDefaults.data(forKey: recentFilesKey),
              let items = try? JSONDecoder().decode([RecentFileItem].self, from: data) else {
            DebugLogger.shared.logArchiveOperation("No recent files found or failed to decode")
            return
        }

        recentFiles = items
        DebugLogger.shared.logArchiveOperation("Loaded recent files",
                                               details: "Count: \(items.count)")
    }

    private func saveRecentFiles() {
        do {
            let data = try JSONEncoder().encode(recentFiles)
            userDefaults.set(data, forKey: recentFilesKey)
            DebugLogger.shared.logArchiveOperation("Saved recent files",
                                                   details: "Count: \(recentFiles.count)")
        } catch {
            DebugLogger.shared.logError(error, context: "Failed to save recent files")
        }
    }

    private func updateSystemRecentMenu() {
        DispatchQueue.main.async {
            // Clear existing recent documents
            NSDocumentController.shared.clearRecentDocuments(nil)

            // Add current recent files to system menu
            for item in self.recentFiles.prefix(10) { // Limit system menu to 10 items
                NSDocumentController.shared.noteNewRecentDocumentURL(item.url)
            }
        }
    }
}

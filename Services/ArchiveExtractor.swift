//
//  ArchiveExtractor.swift
//  Tosho
//
//  Created on 2025/09/27.
//

import Foundation
import AppKit
import UserNotifications

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
        // URLを正規化して保存（ネットワークドライブパスの問題を回避）
        self.url = url.standardized
        self.lastOpened = Date()
        self.fileName = url.lastPathComponent

        // Get file size (ネットワークドライブ対応)
        self.fileSize = Self.getFileSize(for: url)
        self.thumbnailData = thumbnailData
    }

    // ネットワークドライブ対応のファイルサイズ取得
    private static func getFileSize(for url: URL) -> Int64 {
        // まずはリソース値で取得を試行（ネットワークドライブでより確実）
        do {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = resourceValues.fileSize {
                return Int64(fileSize)
            }
        } catch {
            DebugLogger.shared.logArchiveOperation("Failed to get file size via resourceValues",
                                                   details: "URL: \(url.path), Error: \(error.localizedDescription)")
        }

        // フォールバック：従来の方法
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber {
                return size.int64Value
            }
        } catch {
            DebugLogger.shared.logArchiveOperation("Failed to get file size via FileManager",
                                                   details: "URL: \(url.path), Error: \(error.localizedDescription)")
        }

        // どちらも失敗した場合は0を返す
        return 0
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
        let existingFiles = recentFiles.filter { isFileAccessible($0.url) }

        if existingFiles.count != recentFiles.count {
            let removedCount = recentFiles.count - existingFiles.count
            DebugLogger.shared.logArchiveOperation("Cleaned up non-accessible files",
                                                   details: "Removed \(removedCount) files")
            recentFiles = existingFiles
            saveRecentFiles()
            updateSystemRecentMenu()
        }
    }

    // ネットワークドライブ対応のファイルアクセス可能性チェック
    private func isFileAccessible(_ url: URL) -> Bool {
        // まず基本的な存在チェック
        guard FileManager.default.fileExists(atPath: url.path) else {
            // ネットワークドライブの場合、URLResourcesでより詳細にチェック
            if url.scheme == "smb" || url.scheme == "afp" || url.path.contains("/Volumes/") {
                return isNetworkFileAccessible(url)
            }
            return false
        }

        // ファイルが実際に読み取り可能かチェック
        return FileManager.default.isReadableFile(atPath: url.path)
    }

    // ネットワークファイル専用のアクセスチェック
    private func isNetworkFileAccessible(_ url: URL) -> Bool {
        do {
            // リソース値を取得してアクセス可能性を確認
            let resourceValues = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isReadableKey,
                .volumeIsLocalKey
            ])

            // ファイルが存在し、読み取り可能な場合のみtrue
            if let isFile = resourceValues.isRegularFile,
               let isReadable = resourceValues.isReadable {
                return isFile && isReadable
            }

            // リソース値が取得できない場合は保守的にtrue（削除しない）
            return true
        } catch {
            DebugLogger.shared.logArchiveOperation("Network file accessibility check failed",
                                                   details: "URL: \(url.path), Error: \(error.localizedDescription)")
            // エラーの場合は保守的にtrue（削除しない）
            return true
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

    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.fileName = url.lastPathComponent
        self.accessCount = 1
        self.firstAccessed = Date()
        self.lastAccessed = Date()
        self.isFavorite = false
        self.isAutoFavorite = false
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
}

class FavoritesManager: ObservableObject {
    static let shared = FavoritesManager()

    @Published private(set) var fileHistory: [FileHistoryItem] = []
    @Published private(set) var autoFavoriteSuggestions: [FileHistoryItem] = []

    private let userDefaults = UserDefaults.standard
    private let fileHistoryKey = "ToshoFileHistory"
    private let autoFavoriteThreshold = 5

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

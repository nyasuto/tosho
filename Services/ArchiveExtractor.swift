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
    func getSecurityScopedURL() -> URL? {
        guard let bookmarkData = self.bookmarkData else {
            DebugLogger.shared.log("No bookmark data available for: \(fileName)", category: "FileHistoryItem")
            return nil
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                DebugLogger.shared.log("Bookmark data is stale for: \(fileName)", category: "FileHistoryItem")
                return nil
            }

            DebugLogger.shared.log("Successfully resolved security scoped URL for: \(fileName)", category: "FileHistoryItem")
            return url
        } catch {
            DebugLogger.shared.logError(error, context: "Failed to resolve security scoped URL for: \(fileName)")
            return nil
        }
    }

    // セキュリティスコープのアクセス権限を開始
    func startAccessingSecurityScopedResource() -> Bool {
        guard let securityScopedURL = getSecurityScopedURL() else {
            return false
        }

        let success = securityScopedURL.startAccessingSecurityScopedResource()
        if success {
            DebugLogger.shared.log("Started accessing security scoped resource: \(fileName)", category: "FileHistoryItem")
        } else {
            DebugLogger.shared.log("Failed to start accessing security scoped resource: \(fileName)", category: "FileHistoryItem")
        }
        return success
    }

    // セキュリティスコープのアクセス権限を終了
    func stopAccessingSecurityScopedResource() {
        guard let securityScopedURL = getSecurityScopedURL() else {
            return
        }

        securityScopedURL.stopAccessingSecurityScopedResource()
        DebugLogger.shared.log("Stopped accessing security scoped resource: \(fileName)", category: "FileHistoryItem")
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

    // 履歴からファイルを開く際にセキュリティスコープを処理
    func openFileFromHistory(_ url: URL, completion: @escaping (URL?) -> Void) {
        guard let item = fileHistory.first(where: { $0.url == url }) else {
            DebugLogger.shared.log("File not found in history: \(url.lastPathComponent)", category: "FavoritesManager")
            completion(nil)
            return
        }

        // セキュリティスコープのアクセス権限を取得
        if let securityScopedURL = item.getSecurityScopedURL() {
            if securityScopedURL.startAccessingSecurityScopedResource() {
                DebugLogger.shared.log("Successfully started accessing security scoped resource for: \(url.lastPathComponent)", category: "FavoritesManager")
                completion(securityScopedURL)
            } else {
                DebugLogger.shared.log("Failed to start accessing security scoped resource for: \(url.lastPathComponent)", category: "FavoritesManager")
                completion(nil)
            }
        } else {
            // セキュリティスコープが利用できない場合は元のURLを試す
            DebugLogger.shared.log("Security scope not available, trying original URL for: \(url.lastPathComponent)", category: "FavoritesManager")
            completion(url)
        }
    }

    // セキュリティスコープのアクセス権限を終了
    func stopAccessingFileFromHistory(_ url: URL) {
        guard let item = fileHistory.first(where: { $0.url == url }) else {
            return
        }

        item.stopAccessingSecurityScopedResource()
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

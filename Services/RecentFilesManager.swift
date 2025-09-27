//
//  RecentFilesManager.swift
//  Tosho
//
//  Created on 2025/09/27.
//

import Foundation
import AppKit

struct RecentFileItem: Codable, Identifiable {
    let id = UUID()
    let url: URL
    let lastOpened: Date
    let fileName: String
    let fileSize: Int64
    let thumbnailData: Data?

    init(url: URL, thumbnailData: Data? = nil) {
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
                NSDocumentController.shared.noteNewRecentDocument(at: item.url)
            }
        }
    }
}

// MARK: - Notification Extensions
extension Notification.Name {
    static let recentFileOpened = Notification.Name("RecentFileOpened")
}
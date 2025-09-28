import Foundation
import SwiftUI
import AppKit

/// Represents the lifecycle of a single reader window.
/// Owns the `ReaderViewModel`, manages background tasks,
/// and coordinates security scoped resource access.
@MainActor
final class ReadingSession: ObservableObject, Identifiable {
    enum State: String {
        case initializing
        case active
        case closing
        case closed
    }

    let id: UUID
    let sourceURL: URL

    @Published private(set) var state: State = .initializing
    @Published private(set) var viewModel: ReaderViewModel

    private let favoritesManager = FavoritesManager.shared
    private var securityScopedURL: URL?
    private var smartPreloadTask: Task<Void, Never>?
    private var legacyPreloadTask: Task<Void, Never>?

    init(sourceURL: URL, autoLoad: Bool = true) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.viewModel = ReaderViewModel()

        DebugLogger.shared.log("ReadingSession \(id) created for \(sourceURL.lastPathComponent)", category: "ReadingSession")

        setupSecurityScopeIfNeeded()
        if autoLoad {
            attachViewModel()
        } else {
            viewModel.attachToSession(self)
            state = .active
        }
    }

    private func attachViewModel() {
        viewModel.attachToSession(self)
        favoritesManager.recordFileAccess(resolvedURL)
        state = .active
        viewModel.loadInitialContent(from: resolvedURL)
    }

    private func setupSecurityScopeIfNeeded() {
        // If we already have access to the URL, keep it as-is.
        // Attempt to resolve via favorites history to obtain bookmark access when available.
        if let historyItem = favoritesManager.fileHistory.first(where: { $0.url == sourceURL }) {
            var mutableItem = historyItem
            if mutableItem.startAccessingSecurityScopedResource() {
                securityScopedURL = mutableItem.getSecurityScopedURL()
                DebugLogger.shared.log("ReadingSession \(id): acquired security scoped URL", category: "ReadingSession")
            } else {
                DebugLogger.shared.log("ReadingSession \(id): failed to acquire security scope for \(sourceURL.path)", category: "ReadingSession")
            }
        }
    }

    private var resolvedURL: URL {
        securityScopedURL ?? sourceURL
    }

    func registerSmartPreloadTask(_ task: Task<Void, Never>) {
        smartPreloadTask = task
    }

    func registerLegacyPreloadTask(_ task: Task<Void, Never>) {
        legacyPreloadTask = task
    }

    /// Called when the owning window is about to close.
    func prepareForClose() async {
        guard state != .closing && state != .closed else { return }
        state = .closing

        DebugLogger.shared.log("ReadingSession \(id): preparing for close", category: "ReadingSession")
        viewModel.prepareForClose()

        let smartTask = smartPreloadTask
        let legacyTask = legacyPreloadTask

        smartTask?.cancel()
        legacyTask?.cancel()

        smartPreloadTask = nil
        legacyPreloadTask = nil

        if let smartTask {
            _ = await smartTask.value
        }

        if let legacyTask {
            _ = await legacyTask.value
        }

        releaseSecurityScope()
        state = .closed
        DebugLogger.shared.log("ReadingSession \(id): closed", category: "ReadingSession")
    }

    private func releaseSecurityScope() {
        guard securityScopedURL != nil else { return }
        favoritesManager.stopAccessingFileFromHistory(sourceURL)
        securityScopedURL = nil
    }
}

extension ReadingSession {
    static func previewSession() -> ReadingSession {
        let session = ReadingSession(sourceURL: URL(fileURLWithPath: "/tmp/preview.jpg"), autoLoad: false)
        session.viewModel.currentImage = NSImage(size: NSSize(width: 600, height: 800))
        session.viewModel.totalPages = 1
        return session
    }
}

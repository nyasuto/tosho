//
//  ToshoApp.swift
//  Tosho
//
//  Created on 2025/09/27.
//

import SwiftUI
import UniformTypeIdentifiers

@main
struct ToshoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var favoritesManager = FavoritesManager.shared

    var body: some Scene {
        // 従来のメインウィンドウ（ホーム画面）
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, idealWidth: 1200, minHeight: 600, idealHeight: 900)
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.automatic)

        .commands {
            // File Menu Commands
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    openFileInNewWindow()
                }
                .keyboardShortcut("O", modifiers: .command)

                Divider()


                Button("Favorites...") {
                    showFavorites()
                }
                .keyboardShortcut("F", modifiers: [.command, .shift])

                if !favoritesManager.fileHistory.isEmpty {
                    Divider()

                    ForEach(favoritesManager.fileHistory.prefix(10)) { item in
                        Button(item.fileName) {
                            openRecentFileInNewWindow(item.url)
                        }
                    }

                    Divider()

                    Button("Clear Recent Files") {
                        favoritesManager.clearHistory()
                    }
                }
            }

            // View Menu Commands
            CommandMenu("View") {
                Button("Next Page (Space)") {
                    NotificationCenter.default.post(name: .nextPage, object: nil)
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Previous Page (Shift+Space)") {
                    NotificationCenter.default.post(name: .previousPage, object: nil)
                }
                .keyboardShortcut(.space, modifiers: .shift)

                Divider()

                Button("Adjust Forward (+)") {
                    NotificationCenter.default.post(name: .adjustPageForward, object: nil)
                }
                .keyboardShortcut("+", modifiers: [])

                Button("Adjust Backward (-)") {
                    NotificationCenter.default.post(name: .adjustPageBackward, object: nil)
                }
                .keyboardShortcut("-", modifiers: [])

                Divider()

                Button("Toggle Double Page") {
                    NotificationCenter.default.post(name: .toggleDoublePage, object: nil)
                }
                .keyboardShortcut("d", modifiers: [])

                Button("Toggle Reading Direction") {
                    NotificationCenter.default.post(name: .toggleReadingDirection, object: nil)
                }
                .keyboardShortcut("r", modifiers: [])

                Button("Toggle Full Screen") {
                    NotificationCenter.default.post(name: .toggleFullScreen, object: nil)
                }
                .keyboardShortcut("F", modifiers: [.command, .control])

                Divider()

                Button("Show Gallery") {
                    NotificationCenter.default.post(name: .toggleGallery, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command])
            }
        }
    }


    private func showFavorites() {
        NotificationCenter.default.post(name: .showFavorites, object: nil)
    }

    // MARK: - New Window Functions

    private func openFileInNewWindow() {
        DebugLogger.shared.log("ToshoApp: openFileInNewWindow called", category: "ToshoApp")

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true

        var contentTypes: [UTType] = [
            .jpeg, .png, .gif, .tiff, .bmp, .heic, .zip, .data
        ]

        if let webpType = UTType(filenameExtension: "webp") {
            contentTypes.append(webpType)
        }

        if let avifType = UTType(filenameExtension: "avif") {
            contentTypes.append(avifType)
        }

        if let cbzType = UTType(filenameExtension: "cbz") {
            contentTypes.append(cbzType)
        }

        panel.allowedContentTypes = contentTypes

        DebugLogger.shared.log("ToshoApp: Showing file selection panel", category: "ToshoApp")
        if panel.runModal() == .OK {
            if let url = panel.url {
                DebugLogger.shared.log("ToshoApp: File selected: \(url.lastPathComponent)", category: "ToshoApp")
                openDocumentInNewWindow(url)
            } else {
                DebugLogger.shared.log("ToshoApp: No file selected", category: "ToshoApp")
            }
        } else {
            DebugLogger.shared.log("ToshoApp: File selection cancelled", category: "ToshoApp")
        }
    }

    private func openRecentFileInNewWindow(_ url: URL) {
        favoritesManager.openFileFromHistory(url) { securityScopedURL in
            guard let fileURL = securityScopedURL else {
                DebugLogger.shared.log("Failed to get security scoped URL for: \(url.lastPathComponent)", category: "ToshoApp")
                return
            }

            DispatchQueue.main.async {
                self.openDocumentInNewWindow(fileURL)
            }
        }
    }

    private func openDocumentInNewWindow(_ url: URL) {
        DebugLogger.shared.log("ToshoApp: openDocumentInNewWindow called with: \(url.lastPathComponent)", category: "ToshoApp")

        // 新しいリーダーウィンドウを開く（AppDelegateがファイル履歴も記録する）
        DebugLogger.shared.log("ToshoApp: AppDelegate found, calling openNewReaderWindow", category: "ToshoApp")
        appDelegate.openNewReaderWindow(with: url)
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    // ウィンドウを保持するための配列
    private var readerWindows: [NSWindow] = []
    // ウィンドウデリゲートを保持するための配列
    private var windowDelegates: [WindowDelegate] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set app name in menu bar
        if let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String {
            NSApplication.shared.mainMenu?.title = appName
        }

        // Notification監視を設定
        setupNotificationObservers()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running even when all windows are closed
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .openFileInNewWindow,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let url = notification.object as? URL {
                // ファイル履歴に追加
                FavoritesManager.shared.recordFileAccess(url)
                self?.openNewReaderWindow(with: url)
            }
        }
    }

    func openNewReaderWindow(with url: URL) {
        DebugLogger.shared.log("AppDelegate: openNewReaderWindow called for: \(url.lastPathComponent)", category: "AppDelegate")

        DispatchQueue.main.async { [weak self] in
            DebugLogger.shared.log("AppDelegate: Creating NSWindow", category: "AppDelegate")

            // NSWindowを直接作成してマルチウィンドウを実現
            let window = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 1200, height: 900),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )

            DebugLogger.shared.log("AppDelegate: NSWindow created successfully", category: "AppDelegate")

            window.title = url.lastPathComponent
            window.setContentSize(NSSize(width: 1200, height: 900))
            window.center()

            // ウィンドウが閉じられた時にリストから削除
            let windowDelegate = WindowDelegate { [weak self] closedWindow in
                self?.readerWindows.removeAll { $0 === closedWindow }
                self?.windowDelegates.removeAll { $0.window === closedWindow }
                DebugLogger.shared.log("AppDelegate: Window removed from list", category: "AppDelegate")
            }
            windowDelegate.window = window
            window.delegate = windowDelegate

            DebugLogger.shared.log("AppDelegate: Creating ReaderView", category: "AppDelegate")
            let readerView = ReaderView(fileURL: url)
            let hostingView = NSHostingView(rootView: readerView)
            window.contentView = hostingView

            // ウィンドウとデリゲートをリストに追加して保持
            self?.readerWindows.append(window)
            self?.windowDelegates.append(windowDelegate)

            DebugLogger.shared.log("AppDelegate: Making window key and front", category: "AppDelegate")
            window.makeKeyAndOrderFront(nil)

            DebugLogger.shared.log("AppDelegate: New reader window opened successfully, total windows: \(self?.readerWindows.count ?? 0)", category: "AppDelegate")
        }
    }
}

// MARK: - Window Delegate
class WindowDelegate: NSObject, NSWindowDelegate {
    private let onWindowClose: (NSWindow) -> Void
    weak var window: NSWindow?

    init(onWindowClose: @escaping (NSWindow) -> Void) {
        self.onWindowClose = onWindowClose
        super.init()
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            onWindowClose(window)
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let openFile = Notification.Name("tosho.openFile")
    static let openFolder = Notification.Name("tosho.openFolder")
    static let recentFileOpened = Notification.Name("tosho.recentFileOpened")
    static let showFavorites = Notification.Name("tosho.showFavorites")
    static let closeFavorites = Notification.Name("tosho.closeFavorites")
    static let nextPage = Notification.Name("tosho.nextPage")
    static let previousPage = Notification.Name("tosho.previousPage")
    static let adjustPageForward = Notification.Name("tosho.adjustPageForward")
    static let adjustPageBackward = Notification.Name("tosho.adjustPageBackward")
    static let toggleDoublePage = Notification.Name("tosho.toggleDoublePage")
    static let toggleReadingDirection = Notification.Name("tosho.toggleReadingDirection")
    static let toggleFullScreen = Notification.Name("tosho.toggleFullScreen")
    static let toggleGallery = Notification.Name("tosho.toggleGallery")
    static let openFileInNewWindow = Notification.Name("tosho.openFileInNewWindow")
}
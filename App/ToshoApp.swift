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

        if panel.runModal() == .OK {
            if let url = panel.url {
                openDocumentInNewWindow(url)
            }
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
        // ファイル履歴に追加
        favoritesManager.recordFileAccess(url)

        // 新しいリーダーウィンドウを開く
        if let scene = NSApplication.shared.delegate as? AppDelegate {
            scene.openNewReaderWindow(with: url)
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set app name in menu bar
        if let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String {
            NSApplication.shared.mainMenu?.title = appName
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running even when all windows are closed
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func openNewReaderWindow(with url: URL) {
        DebugLogger.shared.log("Opening new reader window for: \(url.lastPathComponent)", category: "AppDelegate")

        DispatchQueue.main.async {
            // NSWindowを直接作成してマルチウィンドウを実現
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1200, height: 900),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )

            window.title = url.lastPathComponent
            window.setContentSize(NSSize(width: 1200, height: 900))
            window.center()

            let readerView = ReaderView(fileURL: url)
            let hostingView = NSHostingView(rootView: readerView)
            window.contentView = hostingView

            window.makeKeyAndOrderFront(nil)

            DebugLogger.shared.log("New reader window opened successfully", category: "AppDelegate")
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
}
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
                    openFileOrFolder()
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
                            openRecentFile(item.url)
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

    private func openFileOrFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        // Use modern allowedContentTypes with custom types for WebP and CBZ
        var contentTypes: [UTType] = [
            .jpeg, .png, .gif, .tiff, .bmp, .heic, .zip, .data
        ]

        // Add WebP support
        if let webpType = UTType(filenameExtension: "webp") {
            contentTypes.append(webpType)
        }

        // Add AVIF support
        if let avifType = UTType(filenameExtension: "avif") {
            contentTypes.append(avifType)
        }

        // Add CBZ support
        if let cbzType = UTType(filenameExtension: "cbz") {
            contentTypes.append(cbzType)
        }

        panel.allowedContentTypes = contentTypes

        if panel.runModal() == .OK {
            if let url = panel.url {
                openAndAddToRecent(url)
            }
        }
    }

    private func openAndAddToRecent(_ url: URL) {
        // 選択されたURLの種類を自動判別
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if exists {
            // ファイル履歴に追加
            favoritesManager.recordFileAccess(url)

            if isDirectory.boolValue {
                // ディレクトリの場合
                NotificationCenter.default.post(name: .openFolder, object: url)
            } else {
                // ファイルの場合、拡張子でさらに判別
                let fileExtension = url.pathExtension.lowercased()
                if fileExtension == "zip" || fileExtension == "cbz" {
                    // アーカイブファイル
                    NotificationCenter.default.post(name: .openFile, object: url)
                } else if ["jpg", "jpeg", "png", "webp", "heic", "tiff", "bmp", "gif", "avif"].contains(fileExtension) {
                    // 画像ファイル
                    NotificationCenter.default.post(name: .openFile, object: url)
                } else {
                    // その他のファイル（とりあえずファイルとして処理）
                    NotificationCenter.default.post(name: .openFile, object: url)
                }
            }
        }
    }

    private func openRecentFile(_ url: URL) {
        openAndAddToRecent(url)
    }


    private func showFavorites() {
        NotificationCenter.default.post(name: .showFavorites, object: nil)
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
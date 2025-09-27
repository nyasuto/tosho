//
//  ToshoApp.swift
//  Tosho
//
//  Created on 2025/09/27.
//

import SwiftUI

@main
struct ToshoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
                Button("Open File...") {
                    openFile()
                }
                .keyboardShortcut("O", modifiers: .command)

                Button("Open Folder...") {
                    openFolder()
                }
                .keyboardShortcut("O", modifiers: [.command, .shift])
            }

            // View Menu Commands
            CommandMenu("View") {
                Button("Right Arrow") {
                    NotificationCenter.default.post(name: .rightArrow, object: nil)
                }
                .keyboardShortcut(.rightArrow, modifiers: [])

                Button("Left Arrow") {
                    NotificationCenter.default.post(name: .leftArrow, object: nil)
                }
                .keyboardShortcut(.leftArrow, modifiers: [])

                Divider()

                Button("Next Page (Space)") {
                    NotificationCenter.default.post(name: .nextPage, object: nil)
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Previous Page (Shift+Space)") {
                    NotificationCenter.default.post(name: .previousPage, object: nil)
                }
                .keyboardShortcut(.space, modifiers: .shift)

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
            }
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.jpeg, .png, .webP, .heic, .tiff, .bmp, .gif]

        if panel.runModal() == .OK {
            if let url = panel.url {
                NotificationCenter.default.post(name: .openFile, object: url)
            }
        }
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        if panel.runModal() == .OK {
            if let url = panel.url {
                NotificationCenter.default.post(name: .openFolder, object: url)
            }
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
}

// MARK: - Notification Names
extension Notification.Name {
    static let openFile = Notification.Name("tosho.openFile")
    static let openFolder = Notification.Name("tosho.openFolder")
    static let nextPage = Notification.Name("tosho.nextPage")
    static let previousPage = Notification.Name("tosho.previousPage")
    static let rightArrow = Notification.Name("tosho.rightArrow")
    static let leftArrow = Notification.Name("tosho.leftArrow")
    static let toggleDoublePage = Notification.Name("tosho.toggleDoublePage")
    static let toggleReadingDirection = Notification.Name("tosho.toggleReadingDirection")
    static let toggleFullScreen = Notification.Name("tosho.toggleFullScreen")
}
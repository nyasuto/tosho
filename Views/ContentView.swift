//
//  ContentView.swift
//  Tosho
//
//  Created on 2025/09/27.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedFileURL: URL?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if let url = selectedFileURL {
                ReaderView(fileURL: url)
            } else {
                WelcomeView(
                    onOpen: openFileOrFolder
                )
            }

            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.3))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            setupNotificationObservers()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") {
                errorMessage = nil
            }
        }, message: {
            if let error = errorMessage {
                Text(error)
            }
        })
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .openFile,
            object: nil,
            queue: .main
        ) { notification in
            if let url = notification.object as? URL {
                selectedFileURL = url
            }
        }

        NotificationCenter.default.addObserver(
            forName: .openFolder,
            object: nil,
            queue: .main
        ) { notification in
            if let url = notification.object as? URL {
                selectedFileURL = url
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }

        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (item, error) in
            guard error == nil,
                  let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }

            DispatchQueue.main.async {
                self.selectedFileURL = url
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
            selectedFileURL = panel.url
        }
    }
}

// MARK: - Welcome View
struct WelcomeView: View {
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)

            Text("Tosho")
                .font(.system(size: 48, weight: .bold, design: .rounded))

            Text("Beautiful Manga Reader for macOS")
                .font(.title3)
                .foregroundColor(.secondary)

            VStack(spacing: 15) {
                Button(action: onOpen) {
                    InstructionCard(
                        icon: "folder.badge.plus",
                        title: "Open...",
                        shortcut: "⌘O",
                        description: "Select files or folders\n(auto-detected)"
                    )
                }
                .buttonStyle(PlainButtonStyle())

                Text("or drag & drop files here")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Supported formats info
                VStack(spacing: 2) {
                    Text("対応ファイル形式:")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text("画像: .jpg, .jpeg, .png, .webp, .heic, .tiff, .bmp, .gif, .avif")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("アーカイブ: .zip, .cbz")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("フォルダ: 画像ファイルを含むディレクトリ")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            }
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Instruction Card
struct InstructionCard: View {
    let icon: String
    let title: String
    let shortcut: String
    let description: String

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.accentColor)

            Text(title)
                .font(.caption)
                .fontWeight(.medium)

            Text(description)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text(shortcut)
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        }
        .frame(width: 160, height: 120)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .shadow(color: .black.opacity(isHovered ? 0.2 : 0.1), radius: isHovered ? 4 : 2, x: 0, y: isHovered ? 2 : 1)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .frame(width: 1200, height: 900)
    }
}

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView(
            onOpen: { print("Open") }
        )
        .frame(width: 1200, height: 900)
    }
}
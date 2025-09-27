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
    @State private var showingRecentFiles = false

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
        .sheet(isPresented: $showingRecentFiles) {
            RecentFilesView()
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

        NotificationCenter.default.addObserver(
            forName: .showRecentFiles,
            object: nil,
            queue: .main
        ) { _ in
            showingRecentFiles = true
        }

        NotificationCenter.default.addObserver(
            forName: .closeRecentFiles,
            object: nil,
            queue: .main
        ) { _ in
            showingRecentFiles = false
        }

        NotificationCenter.default.addObserver(
            forName: .recentFileOpened,
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

// MARK: - Recent Files View
struct RecentFilesView: View {
    @ObservedObject private var recentFilesManager = RecentFilesManager.shared
    @State private var searchText = ""
    @State private var selectedFile: RecentFileItem?
    @Environment(\.presentationMode) var presentationMode

    var filteredFiles: [RecentFileItem] {
        recentFilesManager.getFilteredFiles(searchText: searchText)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerView

                // Search Bar
                searchBarView

                // Files List
                if filteredFiles.isEmpty {
                    emptyStateView
                } else {
                    filesListView
                }
            }
            .navigationTitle("Recent Files")
            .frame(minWidth: 800, minHeight: 600)
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        HStack {
            Text("Recent Files")
                .font(.largeTitle)
                .fontWeight(.bold)

            Spacer()

            HStack(spacing: 12) {
                Button("Clear All") {
                    withAnimation {
                        recentFilesManager.clearAllRecentFiles()
                    }
                }
                .disabled(recentFilesManager.recentFiles.isEmpty)

                Button("Refresh") {
                    recentFilesManager.validateAndCleanupFiles()
                }

                Button("Close") {
                    NotificationCenter.default.post(name: .closeRecentFiles, object: nil)
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding()
    }

    // MARK: - Search Bar
    private var searchBarView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search files...", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onSubmit {
                    // フォーカスを維持
                }

            if !searchText.isEmpty {
                Button("Clear") {
                    searchText = ""
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text(searchText.isEmpty ? "No recent files" : "No files match your search")
                .font(.title2)
                .foregroundColor(.secondary)

            if searchText.isEmpty {
                Text("Open some files to see them here")
                    .font(.body)
                    .foregroundColor(.secondary)
            } else {
                Button("Clear Search") {
                    searchText = ""
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Files List
    private var filesListView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 280, maximum: 350), spacing: 16)
            ], spacing: 16) {
                ForEach(filteredFiles) { file in
                    RecentFileCard(
                        file: file,
                        isSelected: selectedFile?.id == file.id,
                        onTap: {
                            selectedFile = file
                            openFile(file.url)
                        }
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - Actions
    private func openFile(_ url: URL) {
        // Check if file still exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Remove non-existent file
            recentFilesManager.removeRecentFile(url)
            return
        }

        // Open the file
        NotificationCenter.default.post(name: .recentFileOpened, object: url)
        NotificationCenter.default.post(name: .closeRecentFiles, object: nil)
    }
}

// MARK: - Recent File Card
struct RecentFileCard: View {
    let file: RecentFileItem
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Thumbnail
            thumbnailView

            // File Info
            fileInfoView
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(isHovered ? 0.15 : 0.05), radius: isHovered ? 8 : 4, x: 0, y: isHovered ? 4 : 2)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onTap()
        }
        .onAppear {
            loadThumbnail()
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.1)
        } else if isHovered {
            return Color(NSColor.controlBackgroundColor).opacity(0.8)
        } else {
            return Color(NSColor.controlBackgroundColor)
        }
    }

    private var borderColor: Color {
        isSelected ? Color.accentColor : Color.secondary.opacity(0.3)
    }

    // MARK: - Thumbnail View
    private var thumbnailView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 160)

            Group {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(8)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: fileTypeIcon)
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)

                        Text(file.url.pathExtension.uppercased())
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 160)
        }
    }

    // MARK: - File Info View
    private var fileInfoView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(file.fileName)
                .font(.headline)
                .lineLimit(2)
                .truncationMode(.middle)

            HStack {
                Text(file.formattedFileSize)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text(file.formattedLastOpened)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(file.url.path)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Helper Properties
    private var fileTypeIcon: String {
        let ext = file.url.pathExtension.lowercased()
        switch ext {
        case "zip", "cbz":
            return "archivebox.fill"
        case "jpg", "jpeg", "png", "webp", "heic", "tiff", "bmp", "gif", "avif":
            return "photo.fill"
        default:
            return "doc.fill"
        }
    }

    // MARK: - Thumbnail Loading
    private func loadThumbnail() {
        // Use existing thumbnail data if available
        if let thumbnailData = file.thumbnailData,
           let image = NSImage(data: thumbnailData) {
            self.thumbnail = image
            return
        }

        // Generate thumbnail for image files
        let ext = file.url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "webp", "heic", "tiff", "bmp", "gif", "avif"].contains(ext) {
            DispatchQueue.global(qos: .userInitiated).async {
                if let image = NSImage(contentsOf: file.url) {
                    let thumbnailImage = image.resized(to: CGSize(width: 300, height: 200))
                    DispatchQueue.main.async {
                        self.thumbnail = thumbnailImage
                    }
                }
            }
        }
    }
}

// MARK: - NSImage Extension
extension NSImage {
    func resized(to newSize: CGSize) -> NSImage {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: newSize),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .sourceOver,
                  fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}


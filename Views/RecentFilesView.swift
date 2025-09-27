//
//  RecentFilesView.swift
//  Tosho
//
//  Created on 2025/09/27.
//

import SwiftUI
import AppKit

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

// MARK: - Notification Extensions
extension Notification.Name {
    static let closeRecentFiles = Notification.Name("CloseRecentFiles")
}

// MARK: - Preview
struct RecentFilesView_Previews: PreviewProvider {
    static var previews: some View {
        RecentFilesView()
            .frame(width: 1000, height: 700)
    }
}
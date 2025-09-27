//
//  ReaderViewModel.swift
//  Tosho
//
//  Created on 2025/09/27.
//

import SwiftUI
import Combine

class ReaderViewModel: ObservableObject {
    @Published var currentImage: NSImage?
    @Published var currentPageIndex: Int = 0
    @Published var totalPages: Int = 0
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showControls: Bool = false
    @Published var isDoublePageMode: Bool = false

    private var images: [NSImage] = []
    private var fileURLs: [URL] = []
    private let fileLoader = FileLoader()

    var hasNextPage: Bool {
        currentPageIndex < totalPages - 1
    }

    var hasPreviousPage: Bool {
        currentPageIndex > 0
    }

    func loadContent(from url: URL) {
        isLoading = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if url.hasDirectoryPath {
                self?.loadFolder(url)
            } else {
                self?.loadSingleFile(url)
            }
        }
    }

    private func loadFolder(_ folderURL: URL) {
        do {
            let urls = try fileLoader.loadImagesFromFolder(folderURL)
            guard !urls.isEmpty else {
                DispatchQueue.main.async {
                    self.errorMessage = "No image files found in folder"
                    self.isLoading = false
                }
                return
            }

            self.fileURLs = urls
            self.loadImagesFromURLs()
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func loadSingleFile(_ fileURL: URL) {
        guard let image = NSImage(contentsOf: fileURL) else {
            DispatchQueue.main.async {
                self.errorMessage = "Unable to load image"
                self.isLoading = false
            }
            return
        }

        DispatchQueue.main.async {
            self.images = [image]
            self.currentImage = image
            self.totalPages = 1
            self.currentPageIndex = 0
            self.isLoading = false
        }
    }

    private func loadImagesFromURLs() {
        var loadedImages: [NSImage] = []

        for url in fileURLs {
            if let image = NSImage(contentsOf: url) {
                loadedImages.append(image)
            }
        }

        guard !loadedImages.isEmpty else {
            DispatchQueue.main.async {
                self.errorMessage = "No valid images found"
                self.isLoading = false
            }
            return
        }

        DispatchQueue.main.async {
            self.images = loadedImages
            self.totalPages = loadedImages.count
            self.currentPageIndex = 0
            self.currentImage = loadedImages[0]
            self.isLoading = false
        }
    }

    func nextPage() {
        guard hasNextPage else { return }

        let step = isDoublePageMode ? 2 : 1
        let newIndex = min(currentPageIndex + step, totalPages - 1)

        currentPageIndex = newIndex
        updateCurrentImage()
    }

    func previousPage() {
        guard hasPreviousPage else { return }

        let step = isDoublePageMode ? 2 : 1
        let newIndex = max(currentPageIndex - step, 0)

        currentPageIndex = newIndex
        updateCurrentImage()
    }

    func toggleDoublePageMode() {
        isDoublePageMode.toggle()
        updateCurrentImage()
    }

    private func updateCurrentImage() {
        guard !images.isEmpty else { return }

        if isDoublePageMode && currentPageIndex < totalPages - 1 {
            // TODO: Implement double page view
            // For now, just show single page
            currentImage = images[currentPageIndex]
        } else {
            currentImage = images[currentPageIndex]
        }
    }
}

// MARK: - File Loader
class FileLoader {
    private let supportedExtensions = ["jpg", "jpeg", "png", "webp", "heic", "tiff", "bmp", "gif"]

    func loadImagesFromFolder(_ folderURL: URL) throws -> [URL] {
        let fileManager = FileManager.default

        let contents = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        let imageFiles = contents.filter { url in
            let ext = url.pathExtension.lowercased()
            return supportedExtensions.contains(ext)
        }.sorted { url1, url2 in
            url1.lastPathComponent.localizedStandardCompare(url2.lastPathComponent) == .orderedAscending
        }

        return imageFiles
    }
}
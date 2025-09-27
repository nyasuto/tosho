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

    private var imageCache: [Int: NSImage] = [:]
    private var fileURLs: [URL] = []
    private let fileLoader = FileLoader()
    private let cacheSize = 5 // Keep 5 images around current index

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
            self.totalPages = urls.count
            self.loadImageAtIndex(0)
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
            self.imageCache[0] = image
            self.currentImage = image
            self.totalPages = 1
            self.currentPageIndex = 0
            self.isLoading = false
        }
    }

    private func loadImageAtIndex(_ index: Int) {
        guard index >= 0 && index < fileURLs.count else { return }

        // Check if image is already cached
        if let cachedImage = imageCache[index] {
            DispatchQueue.main.async {
                self.currentImage = cachedImage
                self.currentPageIndex = index
                self.isLoading = false
            }
            preloadNearbyImages(around: index)
            return
        }

        // Load image asynchronously
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let url = self.fileURLs[index]
            guard let image = NSImage(contentsOf: url) else {
                DispatchQueue.main.async {
                    self.errorMessage = "Unable to load image at index \(index)"
                    self.isLoading = false
                }
                return
            }

            DispatchQueue.main.async {
                self.imageCache[index] = image
                self.currentImage = image
                self.currentPageIndex = index
                self.isLoading = false
                self.cleanCache()
            }

            self.preloadNearbyImages(around: index)
        }
    }

    private func preloadNearbyImages(around centerIndex: Int) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }

            let range = max(0, centerIndex - self.cacheSize/2)...min(self.fileURLs.count - 1, centerIndex + self.cacheSize/2)

            for i in range {
                if self.imageCache[i] == nil {
                    let url = self.fileURLs[i]
                    if let image = NSImage(contentsOf: url) {
                        DispatchQueue.main.async {
                            self.imageCache[i] = image
                        }
                    }
                }
            }
        }
    }

    private func cleanCache() {
        let indicesToKeep = Set(max(0, currentPageIndex - cacheSize)...min(totalPages - 1, currentPageIndex + cacheSize))

        for index in imageCache.keys {
            if !indicesToKeep.contains(index) {
                imageCache.removeValue(forKey: index)
            }
        }
    }

    func nextPage() {
        guard hasNextPage else { return }

        let step = isDoublePageMode ? 2 : 1
        let newIndex = min(currentPageIndex + step, totalPages - 1)

        if fileURLs.isEmpty {
            // Single image mode
            currentPageIndex = newIndex
            updateCurrentImage()
        } else {
            // Folder mode - load image at new index
            isLoading = true
            loadImageAtIndex(newIndex)
        }
    }

    func previousPage() {
        guard hasPreviousPage else { return }

        let step = isDoublePageMode ? 2 : 1
        let newIndex = max(currentPageIndex - step, 0)

        if fileURLs.isEmpty {
            // Single image mode
            currentPageIndex = newIndex
            updateCurrentImage()
        } else {
            // Folder mode - load image at new index
            isLoading = true
            loadImageAtIndex(newIndex)
        }
    }

    func toggleDoublePageMode() {
        isDoublePageMode.toggle()
        updateCurrentImage()
    }

    private func updateCurrentImage() {
        if let cachedImage = imageCache[currentPageIndex] {
            currentImage = cachedImage
        } else if fileURLs.isEmpty && totalPages == 1 {
            // Single image mode - image should already be set
            return
        } else {
            // Need to load image
            isLoading = true
            loadImageAtIndex(currentPageIndex)
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
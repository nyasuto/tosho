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
    private var document: ToshoDocument?
    private let cacheSize = 5

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
            do {
                let document = ToshoDocument()
                try document.loadContent(from: url)

                DispatchQueue.main.async {
                    self?.document = document
                    self?.totalPages = document.totalPages
                    self?.currentPageIndex = 0
                    self?.loadImageAtIndex(0)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = error.localizedDescription
                    self?.isLoading = false
                }
            }
        }
    }

    private func loadImageAtIndex(_ index: Int) {
        guard let document = document, index >= 0 && index < totalPages else {
            DispatchQueue.main.async {
                self.isLoading = false
            }
            return
        }

        if let cachedImage = imageCache[index] {
            DispatchQueue.main.async {
                self.currentImage = cachedImage
                self.currentPageIndex = index
                self.isLoading = false
            }
            preloadNearbyImages(around: index)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                guard let image = try document.getImage(at: index) else {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Unable to load image at index \(index)"
                        self?.isLoading = false
                    }
                    return
                }

                DispatchQueue.main.async {
                    self?.imageCache[index] = image
                    self?.currentImage = image
                    self?.currentPageIndex = index
                    self?.isLoading = false
                    self?.cleanCache()
                }

                self?.preloadNearbyImages(around: index)
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = error.localizedDescription
                    self?.isLoading = false
                }
            }
        }
    }

    private func preloadNearbyImages(around centerIndex: Int) {
        guard let document = document else { return }

        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }

            let range = max(0, centerIndex - self.cacheSize/2)...min(self.totalPages - 1, centerIndex + self.cacheSize/2)

            for i in range {
                if self.imageCache[i] == nil {
                    do {
                        if let image = try document.getImage(at: i) {
                            DispatchQueue.main.async {
                                self.imageCache[i] = image
                            }
                        }
                    } catch {
                        continue
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

        isLoading = true
        loadImageAtIndex(newIndex)
    }

    func previousPage() {
        guard hasPreviousPage else { return }

        let step = isDoublePageMode ? 2 : 1
        let newIndex = max(currentPageIndex - step, 0)

        isLoading = true
        loadImageAtIndex(newIndex)
    }

    func toggleDoublePageMode() {
        isDoublePageMode.toggle()
        loadImageAtIndex(currentPageIndex)
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
//
//  ReaderViewModel.swift
//  Tosho
//
//  Created on 2025/09/27.
//

import SwiftUI
import Combine

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

class ReaderViewModel: ObservableObject {
    @Published var currentImage: NSImage?
    @Published var secondImage: NSImage?
    @Published var currentPageIndex: Int = 0
    @Published var totalPages: Int = 0
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showControls: Bool = false
    @Published var isDoublePageMode: Bool = false
    @Published var showGallery: Bool = false

    @ObservedObject var readingSettings = ReadingSettings()

    private var imageCache: [Int: NSImage] = [:]
    private var thumbnailCache: [Int: NSImage] = [:]
    private var document: ToshoDocument?
    private let cacheSize = 5
    private let thumbnailSize = CGSize(width: 150, height: 200)

    var hasNextPage: Bool {
        if isDoublePageMode {
            // 見開きモードでは、現在のページ+1が最終ページ未満
            return currentPageIndex + 1 < totalPages
        } else {
            return currentPageIndex < totalPages - 1
        }
    }

    var hasPreviousPage: Bool {
        currentPageIndex > 0
    }

    // 表紙かどうかを判定（1ページ目は表紙として単独表示）
    var isCoverPage: Bool {
        return currentPageIndex == 0
    }

    // 見開きモードで実際に2ページ表示するかどうか
    var shouldShowDoublePages: Bool {
        return isDoublePageMode && !isCoverPage && currentPageIndex + 1 < totalPages
    }

    func loadContent(from url: URL) {
        isLoading = true
        errorMessage = nil
        DebugLogger.shared.log("Starting to load content from: \(url.lastPathComponent)", category: "ReaderViewModel")

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
                DebugLogger.shared.logError(error, category: "ReaderViewModel",
                                            context: "Loading content from \(url.lastPathComponent)")
                DispatchQueue.main.async {
                    self?.errorMessage = error.localizedDescription
                    self?.isLoading = false
                }
            }
        }
    }

    private func loadImageAtIndex(_ index: Int) {
        guard document != nil, index >= 0 && index < totalPages else {
            DispatchQueue.main.async {
                self.isLoading = false
            }
            return
        }

        // 見開きモードで2ページ表示する場合
        if shouldShowDoublePages {
            loadDoublePageImages(startIndex: index)
        } else {
            loadSinglePageImage(index: index)
        }
    }

    private func loadSinglePageImage(index: Int) {
        guard let document = self.document else { return }

        if let cachedImage = imageCache[index] {
            DispatchQueue.main.async {
                self.currentImage = cachedImage
                self.secondImage = nil
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
                    self?.secondImage = nil
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

    private func loadDoublePageImages(startIndex: Int) {
        guard let document = self.document else { return }

        let firstIndex = startIndex
        let secondIndex = startIndex + 1

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                // 1ページ目を取得
                var firstImage: NSImage?
                if let cached = self?.imageCache[firstIndex] {
                    firstImage = cached
                } else {
                    firstImage = try document.getImage(at: firstIndex)
                    if let image = firstImage {
                        DispatchQueue.main.async {
                            self?.imageCache[firstIndex] = image
                        }
                    }
                }

                // 2ページ目を取得
                var secondImage: NSImage?
                if secondIndex < self?.totalPages ?? 0 {
                    if let cached = self?.imageCache[secondIndex] {
                        secondImage = cached
                    } else {
                        secondImage = try document.getImage(at: secondIndex)
                        if let image = secondImage {
                            DispatchQueue.main.async {
                                self?.imageCache[secondIndex] = image
                            }
                        }
                    }
                }

                DispatchQueue.main.async {
                    self?.currentImage = firstImage
                    self?.secondImage = secondImage
                    self?.currentPageIndex = firstIndex
                    self?.isLoading = false
                    self?.cleanCache()
                }

                self?.preloadNearbyImages(around: firstIndex)
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

        var newIndex: Int
        if isDoublePageMode {
            if isCoverPage {
                // 表紙から次へ移動する場合、奇数ページ（1ページ目）へ
                newIndex = 1
            } else {
                // 通常の見開きページング（2ページずつ）
                newIndex = min(currentPageIndex + 2, totalPages - 1)
            }
        } else {
            // 単ページモード
            newIndex = min(currentPageIndex + 1, totalPages - 1)
        }

        isLoading = true
        loadImageAtIndex(newIndex)
    }

    func previousPage() {
        guard hasPreviousPage else { return }

        var newIndex: Int
        if isDoublePageMode {
            if currentPageIndex == 1 {
                // 1ページ目から前へ戻る場合、表紙（0ページ目）へ
                newIndex = 0
            } else {
                // 通常の見開きページング（2ページずつ）
                newIndex = max(currentPageIndex - 2, 0)
            }
        } else {
            // 単ページモード
            newIndex = max(currentPageIndex - 1, 0)
        }

        isLoading = true
        loadImageAtIndex(newIndex)
    }

    // 右から左に読む場合のページ移動
    func moveForward() {
        if readingSettings.readingDirection.isRightToLeft {
            // 右綴じ：右→左の順で読むので、forwardは左方向（nextPage）
            nextPage()
        } else {
            // 左綴じ：左→右の順で読むので、forwardは右方向（nextPage）
            nextPage()
        }
    }

    func moveBackward() {
        if readingSettings.readingDirection.isRightToLeft {
            // 右綴じ：右→左の順で読むので、backwardは右方向（previousPage）
            previousPage()
        } else {
            // 左綴じ：左→右の順で読むので、backwardは左方向（previousPage）
            previousPage()
        }
    }

    func toggleReadingDirection() {
        readingSettings.toggleDirection()
    }

    func toggleDoublePageMode() {
        isDoublePageMode.toggle()

        // モード切り替え時の適切なページ調整
        var adjustedIndex = currentPageIndex
        if isDoublePageMode && currentPageIndex > 0 {
            // 見開きモードに切り替え時、奇数ページ位置に調整
            if currentPageIndex % 2 == 0 && currentPageIndex > 0 {
                adjustedIndex = currentPageIndex - 1
            }
        }

        loadImageAtIndex(adjustedIndex)
    }

    // MARK: - Gallery Functions

    func toggleGallery() {
        showGallery.toggle()
    }

    func jumpToPage(_ pageIndex: Int) {
        guard pageIndex >= 0 && pageIndex < totalPages else { return }
        showGallery = false
        isLoading = true
        loadImageAtIndex(pageIndex)
    }

    func getThumbnail(for pageIndex: Int) -> NSImage? {
        // キャッシュから取得
        if let thumbnail = thumbnailCache[pageIndex] {
            return thumbnail
        }

        // バックグラウンドでサムネイル生成
        generateThumbnail(for: pageIndex)
        return nil
    }

    private func generateThumbnail(for pageIndex: Int) {
        guard pageIndex >= 0 && pageIndex < totalPages,
              let document = document else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                if let image = try document.getImage(at: pageIndex) {
                    let thumbnail = image.resized(to: self.thumbnailSize)
                    DispatchQueue.main.async {
                        self.thumbnailCache[pageIndex] = thumbnail
                    }
                }
            } catch {
                DebugLogger.shared.logError(error, context: "Failed to generate thumbnail for page \(pageIndex)")
            }
        }
    }

    func preloadThumbnails() {
        DispatchQueue.global(qos: .utility).async {
            for i in 0..<self.totalPages {
                if self.thumbnailCache[i] == nil {
                    self.generateThumbnail(for: i)
                }
            }
        }
    }
}

// MARK: - File Loader
class FileLoader {
    private let supportedExtensions = ["jpg", "jpeg", "png", "webp", "heic", "tiff", "bmp", "gif", "avif"]

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

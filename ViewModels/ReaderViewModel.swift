//
//  ReaderViewModel.swift
//  Tosho
//
//  Created on 2025/09/27.
//

import SwiftUI
import Combine
import Foundation

// MARK: - High Performance Image Cache
class ImageCache {
    static let shared = ImageCache()

    // Memory cache (fast, small)
    private let memoryCache = NSCache<NSString, NSImage>()

    // Disk cache (large, slower)
    private let diskCacheURL: URL
    private let diskCacheQueue = DispatchQueue(label: "com.tosho.diskcache", qos: .utility)

    // LRU tracking for disk cache
    private var accessOrder: [String] = []
    private let accessOrderLock = NSLock()
    private let maxDiskItems = 50

    private init() {
        // Setup memory cache
        memoryCache.totalCostLimit = 200 * 1024 * 1024 // 200MB limit
        memoryCache.countLimit = 50 // Max 50 images in memory

        // Setup disk cache directory
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheURL = cacheDir.appendingPathComponent("com.tosho.imagecache")
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)

        DebugLogger.shared.log("ImageCache initialized with memory limit: 200MB, disk cache: \(diskCacheURL.path)", category: "ImageCache")
    }

    func setImage(_ image: NSImage, forKey key: String) {
        // Store in memory cache
        let cost = Int(image.size.width * image.size.height * 4) // Estimate 4 bytes per pixel
        memoryCache.setObject(image, forKey: key as NSString, cost: cost)

        // Store in disk cache asynchronously
        diskCacheQueue.async { [weak self] in
            self?.storeToDisk(image: image, key: key)
        }
    }

    func image(forKey key: String) -> NSImage? {
        // Try memory cache first
        if let cachedImage = memoryCache.object(forKey: key as NSString) {
            DebugLogger.shared.log("Cache hit (memory): \(key)", category: "ImageCache")
            return cachedImage
        }

        // Try disk cache
        if let diskImage = loadFromDisk(key: key) {
            DebugLogger.shared.log("Cache hit (disk): \(key)", category: "ImageCache")
            // Promote to memory cache
            let cost = Int(diskImage.size.width * diskImage.size.height * 4)
            memoryCache.setObject(diskImage, forKey: key as NSString, cost: cost)
            return diskImage
        }

        DebugLogger.shared.log("Cache miss: \(key)", category: "ImageCache")
        return nil
    }

    private func storeToDisk(image: NSImage, key: String) {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return
        }

        let fileURL = diskCacheURL.appendingPathComponent("\(key).png")

        do {
            try pngData.write(to: fileURL)
            updateAccessOrder(key: key)
            cleanupDiskCacheIfNeeded()
        } catch {
            DebugLogger.shared.logError(error, context: "Failed to store image to disk cache: \(key)")
        }
    }

    private func loadFromDisk(key: String) -> NSImage? {
        let fileURL = diskCacheURL.appendingPathComponent("\(key).png")
        guard let image = NSImage(contentsOf: fileURL) else { return nil }

        updateAccessOrder(key: key)
        return image
    }

    private func updateAccessOrder(key: String) {
        accessOrderLock.lock()
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
        accessOrderLock.unlock()
    }

    private func cleanupDiskCacheIfNeeded() {
        accessOrderLock.lock()
        guard accessOrder.count > maxDiskItems else {
            accessOrderLock.unlock()
            return
        }

        let itemsToRemove = accessOrder.count - maxDiskItems
        let keysToRemove = Array(accessOrder.prefix(itemsToRemove))
        accessOrder.removeFirst(itemsToRemove)
        accessOrderLock.unlock()

        for key in keysToRemove {
            let fileURL = diskCacheURL.appendingPathComponent("\(key).png")
            try? FileManager.default.removeItem(at: fileURL)
        }

        DebugLogger.shared.log("Cleaned up \(itemsToRemove) items from disk cache", category: "ImageCache")
    }

    func clearCache() {
        memoryCache.removeAllObjects()
        diskCacheQueue.async { [weak self] in
            guard let self = self else { return }
            try? FileManager.default.removeItem(at: self.diskCacheURL)
            try? FileManager.default.createDirectory(at: self.diskCacheURL, withIntermediateDirectories: true)
            self.accessOrderLock.lock()
            self.accessOrder.removeAll()
            self.accessOrderLock.unlock()
        }
        DebugLogger.shared.log("All caches cleared", category: "ImageCache")
    }

    func removeImages(forFileName fileName: String) {
        let prefix = "\(fileName)_"

        accessOrderLock.lock()
        let keysToRemove = accessOrder.filter { $0.hasPrefix(prefix) }
        accessOrder.removeAll { $0.hasPrefix(prefix) }
        accessOrderLock.unlock()

        guard !keysToRemove.isEmpty else { return }

        keysToRemove.forEach { key in
            memoryCache.removeObject(forKey: key as NSString)
        }

        diskCacheQueue.async { [weak self] in
            guard let self = self else { return }
            keysToRemove.forEach { key in
                let fileURL = self.diskCacheURL.appendingPathComponent("\(key).png")
                try? FileManager.default.removeItem(at: fileURL)
            }
        }

        DebugLogger.shared.log("Removed \(keysToRemove.count) cached images for \(fileName)", category: "ImageCache")
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
    @Published var loadingProgress: Double = 0.0 // 全画像ロード進捗

    @ObservedObject var readingSettings = ReadingSettings()

    // High-performance caching system
    private let imageCache = ImageCache.shared
    private let document = ToshoDocument() // 再利用されるdocumentインスタンス
    private let documentAccessQueue = DispatchQueue(label: "com.tosho.document-access", qos: .userInitiated)
    private weak var session: ReadingSession?
    private var didPrepareForClose = false

    // Smart preloading system
    private var smartPreloadTask: Task<Void, Never>?
    private var currentPreloadRange: Range<Int> = 0..<0
    private let maxConcurrentPreloads = 3
    private var currentFileURL: URL? // セッションが管理

    deinit {
        DebugLogger.shared.log("ReaderViewModel deinitializing", category: "ReaderViewModel")
        prepareForClose()
        DebugLogger.shared.log("ReaderViewModel memory released", category: "ReaderViewModel")
    }

    func attachToSession(_ session: ReadingSession) {
        self.session = session
    }

    func loadInitialContent(from url: URL) {
        loadContent(from: url)
    }

    func prepareForClose() {
        guard !didPrepareForClose else { return }
        didPrepareForClose = true

        smartPreloadTask?.cancel()
        smartPreloadTask = nil

        if let currentFileURL {
            imageCache.removeImages(forFileName: currentFileURL.lastPathComponent)
        }

        currentImage = nil
        secondImage = nil
        currentPreloadRange = 0..<0
        currentFileURL = nil

    }

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
        shouldDisplayDoublePages(at: currentPageIndex)
    }

    private func shouldDisplayDoublePages(at index: Int) -> Bool {
        guard isDoublePageMode else { return false }
        guard index > 0 else { return false }
        return index + 1 < totalPages
    }

    // MARK: - Smart Preloading System

    private func startSmartPreload(around currentIndex: Int) {
        // Cancel previous preload task
        smartPreloadTask?.cancel()

        // Calculate preload range based on reading direction
        let preloadRadius = 2
        let startIndex = max(0, currentIndex - preloadRadius)
        let endIndex = min(totalPages, currentIndex + preloadRadius + 1)
        let newRange = startIndex..<endIndex

        // Skip if range hasn't changed
        guard newRange != currentPreloadRange else { return }
        currentPreloadRange = newRange

        DebugLogger.shared.log("Starting smart preload: range \(startIndex)..<\(endIndex)", category: "ReaderViewModel")

        let task: Task<Void, Never> = Task(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            await self.preloadImagesInRange(newRange, priorityIndex: currentIndex)
        }
        smartPreloadTask = task
        session?.registerSmartPreloadTask(task)
    }

    // MARK: - Phase 3: Enhanced Parallel Preloading

    private func preloadImagesInRange(_ range: Range<Int>, priorityIndex: Int) async {
        guard !Task.isCancelled else { return }

        // Use Phase 3 high-performance parallel processing for archives
        if case .archive = document.contentType {
            await preloadArchiveImagesInRangePhase3(range, priorityIndex: priorityIndex)
        } else {
            // Use Phase 2 smart preloading for folders and single images
            await preloadImagesInRangePhase2(range, priorityIndex: priorityIndex)
        }
    }

    /// Phase 3: High-performance archive preloading with advanced parallel processing
    private func preloadArchiveImagesInRangePhase3(_ range: Range<Int>, priorityIndex: Int) async {
        do {
            DebugLogger.shared.log("Phase 3: Starting high-performance archive preload for range: \(range)", category: "ReaderViewModel")

            // Use ToshoDocument's advanced parallel processing
            let preloadedImages = try await document.preloadImagesInRange(range, priorityIndex: priorityIndex)

            await MainActor.run {
                // Cache all preloaded images
                for (index, image) in preloadedImages {
                    let cacheKey = generateCacheKey(for: index)
                    imageCache.setImage(image, forKey: cacheKey)
                }

                DebugLogger.shared.log("Phase 3: Cached \(preloadedImages.count) images from parallel extraction", category: "ReaderViewModel")
            }
        } catch {
            DebugLogger.shared.logError(error, context: "Phase 3 archive preload failed, falling back to Phase 2")
            await preloadImagesInRangePhase2(range, priorityIndex: priorityIndex)
        }
    }

    /// Phase 2: Smart preloading fallback for non-archive content or Phase 3 failures
    private func preloadImagesInRangePhase2(_ range: Range<Int>, priorityIndex: Int) async {
        guard !Task.isCancelled else { return }

        // Create cache keys for all images in range
        let indices = Array(range)
        let prioritizedIndices = indices.sorted { abs($0 - priorityIndex) < abs($1 - priorityIndex) }

        await withTaskGroup(of: Void.self) { group in
            var activeTaskCount = 0

            for index in prioritizedIndices {
                // Limit concurrent tasks
                if activeTaskCount >= maxConcurrentPreloads {
                    await group.next() // Wait for one to complete
                    activeTaskCount -= 1
                }

                group.addTask { [weak self] in
                    guard let self = self, !Task.isCancelled else { return }
                    await self.preloadSingleImage(at: index)
                }
                activeTaskCount += 1
            }
        }

        DebugLogger.shared.log("Phase 2: Smart preload completed for range: \(range)", category: "ReaderViewModel")
    }

    private func preloadSingleImage(at index: Int) async {
        guard index >= 0 && index < totalPages else { return }

        let cacheKey = generateCacheKey(for: index)

        // Check if already cached
        if imageCache.image(forKey: cacheKey) != nil {
            return // Already cached
        }

        if let image = fetchImageSynchronously(at: index) {
            await MainActor.run {
                imageCache.setImage(image, forKey: cacheKey)
                DebugLogger.shared.log("Preloaded image at index \(index)", category: "ReaderViewModel")
            }
        }
    }

    private func generateCacheKey(for index: Int) -> String {
        guard let fileURL = currentFileURL else { return "unknown_\(index)" }
        let fileName = fileURL.lastPathComponent
        return "\(fileName)_\(index)"
    }

    // MARK: - Enhanced Image Loading

    private func loadImageWithCache(at index: Int) -> NSImage? {
        let cacheKey = generateCacheKey(for: index)

        // Try cache first
        if let cachedImage = imageCache.image(forKey: cacheKey) {
            return cachedImage
        }

        if Thread.isMainThread {
            // Avoid blocking the main thread with expensive decoding work
            return nil
        }

        guard let image = fetchImageSynchronously(at: index) else {
            return nil
        }

        imageCache.setImage(image, forKey: cacheKey)
        return image
    }

    private func fetchImageSynchronously(at index: Int) -> NSImage? {
        documentAccessQueue.sync {
            do {
                return try document.getImage(at: index)
            } catch {
                DebugLogger.shared.logError(error, context: "Failed to load image at index \(index)")
                return nil
            }
        }
    }

    func loadContent(from url: URL) {
        isLoading = true
        errorMessage = nil
        loadingProgress = 0.0
        DebugLogger.shared.log("Starting to load content from: \(url.lastPathComponent)", category: "ReaderViewModel")

        smartPreloadTask?.cancel()
        smartPreloadTask = nil

        if let previousURL = currentFileURL {
            imageCache.removeImages(forFileName: previousURL.lastPathComponent)
        }

        currentImage = nil
        secondImage = nil
        currentPreloadRange = 0..<0

        currentFileURL = url

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                try self.document.loadContent(from: url)

                DispatchQueue.main.async {
                    self.totalPages = self.document.totalPages
                    self.currentPageIndex = 0

                    guard self.totalPages > 0 else {
                        self.isLoading = false
                        self.errorMessage = "このアーカイブには表示可能なページがありません"
                        return
                    }

                    self.isLoading = true
                    self.loadImageAtIndex(0)
                    self.startSmartPreload(around: 0)
                }
            } catch {
                DebugLogger.shared.logError(error, category: "ReaderViewModel",
                                            context: "Loading content from \(url.lastPathComponent)")
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func present(primary: NSImage, secondary: NSImage?, index: Int) {
        currentImage = primary
        let showDouble = shouldDisplayDoublePages(at: index)
        secondImage = showDouble ? secondary : nil
        currentPageIndex = index
        isLoading = false
        loadingProgress = 1.0
    }

    private func loadImageAtIndex(_ index: Int) {
        guard index >= 0 && index < totalPages else {
            isLoading = false
            return
        }

        let wantsDouble = shouldDisplayDoublePages(at: index)

        if wantsDouble {
            let firstCached = loadImageWithCache(at: index)
            let secondCached = (index + 1 < totalPages) ? loadImageWithCache(at: index + 1) : nil

            if let firstCached = firstCached, secondCached != nil {
                present(primary: firstCached, secondary: secondCached, index: index)
                return
            }

            loadDoublePageImages(startIndex: index)
        } else {
            if let cachedImage = loadImageWithCache(at: index) {
                present(primary: cachedImage, secondary: nil, index: index)
                return
            }

            loadSinglePageImage(index: index)
        }
    }

    private func loadSinglePageImage(index: Int) {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            DebugLogger.shared.log("Background fetch started for page \(index)", category: "ReaderViewModel")
            let image = self.loadImageWithCache(at: index)

            DispatchQueue.main.async {
                if let image {
                    self.present(primary: image, secondary: nil, index: index)
                } else {
                    self.errorMessage = "Unable to load image at index \(index)"
                    self.isLoading = false
                }
            }
        }
    }

    private func loadDoublePageImages(startIndex: Int) {
        isLoading = true

        let firstIndex = startIndex
        let secondIndex = startIndex + 1

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            DebugLogger.shared.log("Background fetch started for double-page \(firstIndex)", category: "ReaderViewModel")
            let firstImage = self.loadImageWithCache(at: firstIndex)
            let secondImage = secondIndex < self.totalPages ? self.loadImageWithCache(at: secondIndex) : nil

            DispatchQueue.main.async {
                guard let firstImage else {
                    self.errorMessage = "Unable to load images at index \(firstIndex)"
                    self.isLoading = false
                    return
                }

                if self.shouldDisplayDoublePages(at: firstIndex) && secondImage == nil {
                    self.errorMessage = "Unable to load images at index \(secondIndex)"
                    self.isLoading = false
                    return
                }

                self.present(primary: firstImage, secondary: secondImage, index: firstIndex)
            }
        }
    }

    // MARK: - Paging

    func nextPage() {
        guard hasNextPage && !isLoading else { return }

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

        loadImageAtIndex(newIndex)
        startSmartPreload(around: newIndex)
    }

    func previousPage() {
        guard hasPreviousPage && !isLoading else { return }

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

        loadImageAtIndex(newIndex)
        startSmartPreload(around: newIndex)
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

    // MARK: - 見開きモード用1ページ単位調整

    func adjustPageForward() {
        guard !isLoading else { return }

        guard isDoublePageMode else {
            // 単ページモードでは通常のnextPageと同じ
            nextPage()
            return
        }

        guard currentPageIndex < totalPages - 1 else { return }

        var newIndex = currentPageIndex + 1

        // 表紙（0ページ）から1ページ目に移動する場合
        if currentPageIndex == 0 {
            newIndex = 1
        } else {
            // 通常の1ページ進み
            newIndex = min(currentPageIndex + 1, totalPages - 1)
        }

        loadImageAtIndex(newIndex)
    }

    func adjustPageBackward() {
        guard !isLoading else { return }

        guard isDoublePageMode else {
            // 単ページモードでは通常のpreviousPageと同じ
            previousPage()
            return
        }

        guard currentPageIndex > 0 else { return }

        var newIndex = currentPageIndex - 1

        // 1ページ目から表紙（0ページ）に戻る場合
        if currentPageIndex == 1 {
            newIndex = 0
        } else {
            // 通常の1ページ戻り
            newIndex = max(currentPageIndex - 1, 0)
        }

        loadImageAtIndex(newIndex)
    }

    // MARK: - Gallery Functions

    func toggleGallery() {
        showGallery.toggle()
    }

    func jumpToPage(_ pageIndex: Int) {
        guard pageIndex >= 0 && pageIndex < totalPages && !isLoading else { return }
        showGallery = false

        loadImageAtIndex(pageIndex)
        startSmartPreload(around: pageIndex)
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

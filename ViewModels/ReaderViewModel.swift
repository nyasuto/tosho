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
    @Published var loadingProgress: Double = 0.0 // 全画像ロード進捗

    @ObservedObject var readingSettings = ReadingSettings()

    private var allImages: [NSImage] = [] // 全画像を事前ロード
    private var thumbnailCache: [Int: NSImage] = [:]
    private let document = ToshoDocument() // 再利用されるdocumentインスタンス
    private let thumbnailSize = CGSize(width: 90, height: 130)
    private let favoritesManager = FavoritesManager.shared
    private var preloadTask: Task<Void, Never>? // 事前ロードタスク
    private var currentFileURL: URL? // セキュリティスコープ管理用

    deinit {
        // セキュリティスコープのアクセス権限を終了
        if let fileURL = currentFileURL {
            favoritesManager.stopAccessingFileFromHistory(fileURL)
        }
        preloadTask?.cancel()
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
        return isDoublePageMode && !isCoverPage && currentPageIndex + 1 < totalPages
    }

    func loadContent(from url: URL) {
        isLoading = true
        errorMessage = nil
        loadingProgress = 0.0
        DebugLogger.shared.log("Starting to load content from: \(url.lastPathComponent)", category: "ReaderViewModel")

        // 既存のプリロードタスクをキャンセル
        preloadTask?.cancel()

        // 画像状態をリセット
        currentImage = nil
        secondImage = nil
        allImages.removeAll()
        thumbnailCache.removeAll() // サムネイルキャッシュもクリア

        // 現在のファイルURLを保存（セキュリティスコープ管理用）
        currentFileURL = url

        // ファイルアクセスを記録
        favoritesManager.recordFileAccess(url)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                guard let self = self else { return }
                try self.document.loadContent(from: url)

                DispatchQueue.main.async {
                    self.totalPages = self.document.totalPages
                    self.currentPageIndex = 0

                    // アーカイブの場合は全画像を事前ロード
                    if case .archive = self.document.contentType {
                        self.preloadAllImages()
                    } else {
                        // フォルダや単一画像の場合は従来通り
                        self.loadImageAtIndex(0)
                    }
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

    // MARK: - 全画像事前ロード機能

    private func preloadAllImages() {
        guard totalPages > 0 else { return }

        DebugLogger.shared.log("Starting preload of all \(totalPages) images", category: "ReaderViewModel")

        preloadTask = Task { [weak self] in
            guard let self = self else { return }
            let totalPagesCount = self.totalPages
            var loadedImages: [NSImage] = Array(repeating: NSImage(), count: totalPagesCount)

            for index in 0..<totalPagesCount {
                // キャンセルチェック
                if Task.isCancelled { return }

                do {
                    if let image = try self.document.getImage(at: index) {
                        loadedImages[index] = image

                        // 進捗を更新（メインスレッド）
                        await MainActor.run { [weak self] in
                            self?.loadingProgress = Double(index + 1) / Double(totalPagesCount)

                            // 最初の画像が読み込まれたら即座に表示
                            if index == 0 {
                                self?.allImages = loadedImages
                                self?.displayImagesFromCache(index: 0)
                            }
                        }
                    }
                } catch {
                    DebugLogger.shared.logError(error, context: "Preloading image at index \(index)")
                    // エラーが発生しても続行
                    continue
                }

                // ネットワークドライブの負荷軽減のため少し待機
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
            }

            // 全て完了
            await MainActor.run { [weak self] in
                self?.allImages = loadedImages
                self?.isLoading = false
                self?.loadingProgress = 1.0
                DebugLogger.shared.log("Preload completed for \(totalPagesCount) images", category: "ReaderViewModel")
            }
        }
    }

    private func displayImagesFromCache(index: Int) {
        guard index >= 0 && index < allImages.count else {
            isLoading = false
            return
        }

        if shouldShowDoublePages {
            // 見開きモード
            currentImage = allImages[index]
            secondImage = (index + 1 < allImages.count) ? allImages[index + 1] : nil
        } else {
            // 単ページモード
            currentImage = allImages[index]
            secondImage = nil
        }

        currentPageIndex = index
        isLoading = false
    }

    private func loadImageAtIndex(_ index: Int) {
        // 全画像がロード済みの場合はキャッシュから即座に表示
        if !allImages.isEmpty && index < allImages.count {
            displayImagesFromCache(index: index)
            return
        }

        // 従来の段階的読み込み（フォルダや単一画像用）
        guard index >= 0 && index < totalPages else {
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

        // 全画像プリロード方式では古いキャッシュシステムは使用しない

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                guard let self = self,
                      let image = try self.document.getImage(at: index) else {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Unable to load image at index \(index)"
                        self?.isLoading = false
                    }
                    return
                }

                DispatchQueue.main.async {
                    // 全画像プリロード方式では古いキャッシュシステムは使用しない
                    self.currentImage = image
                    self.secondImage = nil
                    self.currentPageIndex = index
                    self.isLoading = false
                    // 全画像プリロード方式ではキャッシュクリーンアップ不要
                }

                // 全画像プリロード方式では不要
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.errorMessage = error.localizedDescription
                    self?.isLoading = false
                }
            }
        }
    }

    private func loadDoublePageImages(startIndex: Int) {

        let firstIndex = startIndex
        let secondIndex = startIndex + 1

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                guard let self = self else { return }
                // 1ページ目を取得
                let firstImage = try self.document.getImage(at: firstIndex)

                // 2ページ目を取得
                var secondImage: NSImage?
                if secondIndex < self.totalPages {
                    secondImage = try self.document.getImage(at: secondIndex)
                }

                DispatchQueue.main.async {
                    self.currentImage = firstImage
                    self.secondImage = secondImage
                    self.currentPageIndex = firstIndex
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.errorMessage = error.localizedDescription
                    self?.isLoading = false
                }
            }
        }
    }

    // MARK: - 古いキャッシュシステムは削除（全画像プリロード方式では不要）

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

        // 全画像プリロード方式では即座に表示
        if !allImages.isEmpty {
            displayImagesFromCache(index: newIndex)
        } else {
            isLoading = true
            loadImageAtIndex(newIndex)
        }
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

        // 全画像プリロード方式では即座に表示
        if !allImages.isEmpty {
            displayImagesFromCache(index: newIndex)
        } else {
            isLoading = true
            loadImageAtIndex(newIndex)
        }
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

        // 全画像プリロード方式では即座に表示
        if !allImages.isEmpty {
            displayImagesFromCache(index: newIndex)
        } else {
            isLoading = true
            loadImageAtIndex(newIndex)
        }
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

        // 全画像プリロード方式では即座に表示
        if !allImages.isEmpty {
            displayImagesFromCache(index: newIndex)
        } else {
            isLoading = true
            loadImageAtIndex(newIndex)
        }
    }

    // MARK: - Gallery Functions

    func toggleGallery() {
        showGallery.toggle()
    }

    func jumpToPage(_ pageIndex: Int) {
        guard pageIndex >= 0 && pageIndex < totalPages && !isLoading else { return }
        showGallery = false

        // 全画像プリロード方式では即座に表示
        if !allImages.isEmpty {
            displayImagesFromCache(index: pageIndex)
        } else {
            isLoading = true
            loadImageAtIndex(pageIndex)
        }
    }

    func getThumbnail(for pageIndex: Int) -> NSImage? {
        // キャッシュから取得
        if let thumbnail = thumbnailCache[pageIndex] {
            return thumbnail
        }

        // 全画像がプリロード済みの場合は即座にサムネイル生成
        if !allImages.isEmpty && pageIndex < allImages.count {
            let thumbnail = allImages[pageIndex].resized(to: thumbnailSize)
            thumbnailCache[pageIndex] = thumbnail
            return thumbnail
        }

        // バックグラウンドでサムネイル生成
        generateThumbnail(for: pageIndex)
        return nil
    }

    private func generateThumbnail(for pageIndex: Int) {
        guard pageIndex >= 0 && pageIndex < totalPages else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                guard let self = self else { return }
                if let image = try self.document.getImage(at: pageIndex) {
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

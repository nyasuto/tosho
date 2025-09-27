//
//  ToshoDocument.swift
//  Tosho
//
//  Created on 2025/09/27.
//

import Foundation
import AppKit

enum ContentType {
    case singleImage(URL)
    case folder([URL])
    case archive(URL, [String])
}

class ToshoDocument: ObservableObject {
    @Published var contentType: ContentType?
    @Published var totalPages: Int = 0
    @Published var currentPageIndex: Int = 0

    private let archiveExtractor = ArchiveExtractor()

    func loadContent(from url: URL) throws {
        if url.hasDirectoryPath {
            try loadFolder(url)
        } else if isArchiveFile(url) {
            try loadArchive(url)
        } else {
            loadSingleImage(url)
        }
    }

    func getImage(at index: Int) throws -> NSImage? {
        guard index >= 0 && index < totalPages else {
            throw ToshoDocumentError.indexOutOfRange
        }

        switch contentType {
        case .singleImage(let url):
            return NSImage(contentsOf: url)

        case .folder(let urls):
            guard index < urls.count else { return nil }
            return NSImage(contentsOf: urls[index])

        case .archive(let archiveURL, let imageList):
            return try archiveExtractor.extractSingleImage(at: index, from: archiveURL, imageList: imageList)

        case .none:
            return nil
        }
    }

    func getCurrentImageURL() -> URL? {
        switch contentType {
        case .singleImage(let url):
            return url
        case .folder(let urls):
            guard currentPageIndex < urls.count else { return nil }
            return urls[currentPageIndex]
        case .archive:
            return nil
        case .none:
            return nil
        }
    }

    func getPageInfo(at index: Int) -> String? {
        switch contentType {
        case .singleImage(let url):
            return url.lastPathComponent
        case .folder(let urls):
            guard index < urls.count else { return nil }
            return urls[index].lastPathComponent
        case .archive(_, let imageList):
            guard index < imageList.count else { return nil }
            return imageList[index]
        case .none:
            return nil
        }
    }

    private func loadSingleImage(_ url: URL) {
        contentType = .singleImage(url)
        totalPages = 1
        currentPageIndex = 0
    }

    private func loadFolder(_ folderURL: URL) throws {
        let fileLoader = FileLoader()
        let urls = try fileLoader.loadImagesFromFolder(folderURL)
        guard !urls.isEmpty else {
            throw ToshoDocumentError.noImagesFound
        }

        contentType = .folder(urls)
        totalPages = urls.count
        currentPageIndex = 0
    }

    private func loadArchive(_ archiveURL: URL) throws {
        let imageList = try archiveExtractor.getImageList(from: archiveURL)
        guard !imageList.isEmpty else {
            throw ToshoDocumentError.noImagesFound
        }

        contentType = .archive(archiveURL, imageList)
        totalPages = imageList.count
        currentPageIndex = 0
    }

    private func isArchiveFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "zip" || ext == "cbz"
    }
}

enum ToshoDocumentError: Error, LocalizedError {
    case noImagesFound
    case indexOutOfRange
    case invalidContent

    var errorDescription: String? {
        switch self {
        case .noImagesFound:
            return "No image files found"
        case .indexOutOfRange:
            return "Page index out of range"
        case .invalidContent:
            return "Invalid content type"
        }
    }
}
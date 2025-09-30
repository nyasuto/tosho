import Foundation
import AppKit

struct FileNavigatorItem: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    var children: [FileNavigatorItem]?

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

@MainActor
final class FileNavigatorViewModel: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var items: [FileNavigatorItem] = []
    @Published var selectedURL: URL?
    @Published var sortKey: SortKey = .name {
        didSet {
            rebuildSortedItems()
        }
    }
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastRefreshed: Date?

    enum SortKey: String, CaseIterable {
        case name = "名前"
        case modified = "更新日"
    }

    private let fileManager = FileManager.default
    private let userDefaults = UserDefaults.standard
    private let rootBookmarkKey = "FinderRootBookmark"
    private let maxInitialDepth = 1
    private let cacheTTL: TimeInterval = 1200 // 20 minutes

    private var securityScopedRoot: URL?
    private var treeLoadTask: Task<Void, Never>?
    private var directoryLoadTasks: [URL: Task<Void, Never>] = [:]

    private struct CachedEntry {
        var item: FileNavigatorItem
        var timestamp: Date
    }

    private var cache: [URL: CachedEntry] = [:]

    private let directoryOptions: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
    private let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "tiff", "bmp", "heic", "webp", "avif",
        "zip", "cbz"
    ]

    init() {
        restoreRootFromBookmark()
    }

    deinit {
        treeLoadTask?.cancel()
        directoryLoadTasks.values.forEach { $0.cancel() }
        securityScopedRoot?.stopAccessingSecurityScopedResource()
    }

    var hasRoot: Bool { rootURL != nil }

    func updateRoot(to url: URL) {
        startAccessing(url)
        persistBookmark(for: url)
        rootURL = url
        refreshTree(force: true)
    }

    func clearRoot() {
        treeLoadTask?.cancel()
        directoryLoadTasks.values.forEach { $0.cancel() }
        directoryLoadTasks.removeAll()

        securityScopedRoot?.stopAccessingSecurityScopedResource()
        securityScopedRoot = nil

        rootURL = nil
        items = []
        selectedURL = nil
        isLoading = false
        lastRefreshed = nil
        cache.removeAll()

        userDefaults.removeObject(forKey: rootBookmarkKey)
    }

    func refreshTree(force: Bool = false) {
        treeLoadTask?.cancel()

        guard let rootURL else {
            items = []
            selectedURL = nil
            lastRefreshed = nil
            return
        }

        if !force, let cached = cache[rootURL], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            let sorted = sortItem(cached.item)
            items = [sorted]
            cache[rootURL] = CachedEntry(item: sorted, timestamp: cached.timestamp)
            if selectedURL == nil { selectedURL = cached.item.url }
            isLoading = false
            lastRefreshed = cached.timestamp
            return
        }

        isLoading = true
        let fm = fileManager
        let supported = supportedExtensions
        let options = directoryOptions
        let targetURL = rootURL
        let maxDepth = maxInitialDepth

        treeLoadTask = Task(priority: .userInitiated) { [weak self] in
            let result = FileNavigatorViewModel.makeItem(
                at: targetURL,
                depth: 0,
                maxDepth: maxDepth,
                supportedExtensions: supported,
                fileManager: fm,
                options: options
            )

            await MainActor.run {
                guard let self = self else { return }
                guard self.rootURL == targetURL else { return }
                if Task.isCancelled { return }

                if let result {
                    let sorted = self.sortItem(result)
                    self.items = [sorted]
                    if self.selectedURL == nil { self.selectedURL = result.url }
                    let now = Date()
                    self.cache[targetURL] = CachedEntry(item: sorted, timestamp: now)
                    self.lastRefreshed = now
                } else {
                    self.items = []
                    self.selectedURL = nil
                    self.cache.removeValue(forKey: targetURL)
                    self.lastRefreshed = Date()
                }

                self.isLoading = false
            }
        }
    }

    func children(of url: URL) -> [FileNavigatorItem] {
        if shouldReloadChildren(for: url) {
            enqueueChildLoad(for: url)
        }
        return currentChildren(of: url)
    }

    func forceRefreshDirectory(at url: URL) {
        if url == rootURL {
            refreshTree(force: true)
            return
        }
        directoryLoadTasks[url]?.cancel()
        directoryLoadTasks[url] = nil
        cache.removeValue(forKey: url)
        enqueueChildLoad(for: url)
    }

    func isDirectory(_ url: URL) -> Bool {
        guard let root = items.first else { return false }
        return findItem(in: root, matching: url)?.isDirectory ?? false
    }

    func isSupportedFile(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    func lastUpdated(for url: URL) -> Date? {
        cache[url]?.timestamp
    }

    func lastModified(for url: URL) -> Date? {
        do {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            return values.contentModificationDate
        } catch {
            return nil
        }
    }

    // MARK: - Private helpers

    private func currentChildren(of url: URL) -> [FileNavigatorItem] {
        guard let root = items.first,
              let item = findItem(in: root, matching: url) else { return [] }
        return item.children ?? []
    }

    private func shouldReloadChildren(for url: URL) -> Bool {
        guard let entry = cache[url] else { return true }
        let expired = Date().timeIntervalSince(entry.timestamp) >= cacheTTL
        let hasChildren = entry.item.children != nil
        return expired || !hasChildren
    }

    private func enqueueChildLoad(for url: URL) {
        guard directoryLoadTasks[url] == nil else { return }
        guard isDirectory(url) else { return }

        let depth = depthFromRoot(of: url)
        let fm = fileManager
        let supported = supportedExtensions
        let options = directoryOptions
        let nextMaxDepth = depth + 1

        directoryLoadTasks[url] = Task(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            let children = FileNavigatorViewModel.loadDirectoryEntries(
                for: url,
                depth: depth,
                maxDepth: nextMaxDepth,
                supportedExtensions: supported,
                fileManager: fm,
                options: options
            )

            await MainActor.run {
                self.applyChildren(children, to: url)
                self.directoryLoadTasks[url] = nil
            }
        }
    }

    private func applyChildren(_ children: [FileNavigatorItem], to url: URL) {
        guard !items.isEmpty else { return }

        let sortedChildren = sortedChildren(children)
        items = items.map { update(item: $0, target: url, newChildren: sortedChildren) }
        cache[url] = CachedEntry(item: FileNavigatorItem(url: url, isDirectory: true, children: sortedChildren), timestamp: Date())

        if let root = items.first, let rootURL = rootURL {
            let sortedRoot = sortItem(root)
            items = [sortedRoot]
            let rootTimestamp = cache[rootURL]?.timestamp ?? Date()
            cache[rootURL] = CachedEntry(item: sortedRoot, timestamp: rootTimestamp)
            if url == rootURL {
                lastRefreshed = rootTimestamp
            }
        }
    }

    private func rebuildSortedItems() {
        guard let rootURL else { return }

        cache = cache.reduce(into: [:]) { result, entry in
            let (url, cachedEntry) = entry
            let sortedItem = sortItem(cachedEntry.item)
            result[url] = CachedEntry(item: sortedItem, timestamp: cachedEntry.timestamp)
        }

        if let cachedRoot = cache[rootURL] {
            items = [cachedRoot.item]
            lastRefreshed = cachedRoot.timestamp
        }
    }


    private func sortedChildren(_ children: [FileNavigatorItem]) -> [FileNavigatorItem] {
        children.map { sortItem($0) }.sorted(by: compare(_:_:))
    }

    private func sortItem(_ item: FileNavigatorItem) -> FileNavigatorItem {
        var copy = item
        if let children = item.children {
            copy.children = sortedChildren(children)
        }
        return copy
    }

    private func compare(_ lhs: FileNavigatorItem, _ rhs: FileNavigatorItem) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory && !rhs.isDirectory
        }

        switch sortKey {
        case .name:
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        case .modified:
            let lhsDate = lastModified(for: lhs.url) ?? .distantPast
            let rhsDate = lastModified(for: rhs.url) ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhsDate > rhsDate
        }
    }

    private func update(item: FileNavigatorItem, target: URL, newChildren: [FileNavigatorItem]) -> FileNavigatorItem {
        var copy = item
        if item.url == target {
            copy.children = newChildren
            return copy
        }

        if let existingChildren = item.children {
            var updatedChildren = existingChildren
            var changed = false
            for index in existingChildren.indices {
                let updated = update(item: existingChildren[index], target: target, newChildren: newChildren)
                if updated.url == target || updated.children != existingChildren[index].children {
                    updatedChildren[index] = updated
                    changed = true
                }
            }
            if changed {
                copy.children = updatedChildren
            }
        }
        return copy
    }

    private func depthFromRoot(of url: URL) -> Int {
        guard let rootURL else { return 0 }
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let targetComponents = url.standardizedFileURL.pathComponents
        return max(targetComponents.count - rootComponents.count, 0)
    }

    private func findItem(in item: FileNavigatorItem, matching url: URL) -> FileNavigatorItem? {
        if item.url == url { return item }
        guard let children = item.children else { return nil }
        for child in children {
            if let match = findItem(in: child, matching: url) {
                return match
            }
        }
        return nil
    }

    private func startAccessing(_ url: URL) {
        securityScopedRoot?.stopAccessingSecurityScopedResource()
        if url.startAccessingSecurityScopedResource() {
            securityScopedRoot = url
        } else {
            securityScopedRoot = nil
        }
    }

    private func persistBookmark(for url: URL) {
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            userDefaults.set(bookmark, forKey: rootBookmarkKey)
        } catch {
            DebugLogger.shared.logError(error, context: "Failed to save finder root bookmark")
        }
    }

    private func restoreRootFromBookmark() {
        guard let bookmark = userDefaults.data(forKey: rootBookmarkKey) else { return }
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
            startAccessing(url)
            if isStale {
                persistBookmark(for: url)
            }
            rootURL = url
            refreshTree()
        } catch {
            DebugLogger.shared.logError(error, context: "Failed to restore finder root bookmark")
            userDefaults.removeObject(forKey: rootBookmarkKey)
        }
    }

    // MARK: - Static helpers

    nonisolated private static func makeItem(
        at url: URL,
        depth: Int,
        maxDepth: Int,
        supportedExtensions: Set<String>,
        fileManager: FileManager,
        options: FileManager.DirectoryEnumerationOptions
    ) -> FileNavigatorItem? {
        if Task.isCancelled { return nil }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }

        if isDirectory.boolValue {
            var children: [FileNavigatorItem]? = nil
            if depth < maxDepth {
                children = loadDirectoryEntries(
                    for: url,
                    depth: depth,
                    maxDepth: maxDepth,
                    supportedExtensions: supportedExtensions,
                    fileManager: fileManager,
                    options: options
                )
            }
            return FileNavigatorItem(url: url, isDirectory: true, children: children)
        } else {
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
                return nil
            }
            return FileNavigatorItem(url: url, isDirectory: false, children: nil)
        }
    }

    nonisolated private static func loadDirectoryEntries(
        for directory: URL,
        depth: Int,
        maxDepth: Int,
        supportedExtensions: Set<String>,
        fileManager: FileManager,
        options: FileManager.DirectoryEnumerationOptions
    ) -> [FileNavigatorItem] {
        if Task.isCancelled { return [] }

        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil, options: options.union([.skipsSubdirectoryDescendants])) else {
            return []
        }

        var collected: [URL] = []
        for case let child as URL in enumerator {
            collected.append(child)
        }

        return collected.compactMap { child in
            makeItem(
                at: child,
                depth: depth + 1,
                maxDepth: maxDepth,
                supportedExtensions: supportedExtensions,
                fileManager: fileManager,
                options: options
            )
        }
    }
}

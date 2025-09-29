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
    @StateObject private var navigator = FileNavigatorViewModel()
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingFavorites = false

    var body: some View {
        ZStack {
            if navigator.hasRoot {
                NavigationSplitView {
                    FinderSidebarView(
                        navigator: navigator,
                        onSelectRoot: selectLibraryFolder,
                        onClearRoot: { navigator.clearRoot() },
                        onRefresh: { navigator.refreshTree(force: true) },
                        onSelectURL: { navigator.selectedURL = $0 },
                        onOpenFile: openInNewWindow
                    )
                } detail: {
                    FinderDetailView(
                        navigator: navigator,
                        onOpenFile: openInNewWindow,
                        onSelectRoot: selectLibraryFolder,
                        onOpenDialog: openFileOrFolder
                    )
                }
            } else {
                FinderWelcomeView(
                    onChooseRoot: selectLibraryFolder,
                    onOpenDialog: openFileOrFolder
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
        .sheet(isPresented: $showingFavorites) {
            FavoritesView()
        }
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .openFile,
            object: nil,
            queue: .main
        ) { notification in
            if let url = notification.object as? URL {
                self.openInNewWindow(url)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .openFolder,
            object: nil,
            queue: .main
        ) { notification in
            if let url = notification.object as? URL {
                self.openInNewWindow(url)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .recentFileOpened,
            object: nil,
            queue: .main
        ) { notification in
            if let url = notification.object as? URL {
                self.openInNewWindow(url)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .showFavorites,
            object: nil,
            queue: .main
        ) { _ in
            showingFavorites = true
        }

        NotificationCenter.default.addObserver(
            forName: .closeFavorites,
            object: nil,
            queue: .main
        ) { _ in
            showingFavorites = false
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
                self.openInNewWindow(url)
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
            if let url = panel.url {
                // 新しいウィンドウで開く
                openInNewWindow(url)
            }
        }
    }

    private func openInNewWindow(_ url: URL) {
        DebugLogger.shared.log("ContentView: Attempting to open file in new window: \(url.lastPathComponent)", category: "ContentView")

        // NotificationCenterを通してファイルオープンを要求
        NotificationCenter.default.post(name: .openFileInNewWindow, object: url)
    }

    private func selectLibraryFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"

        if panel.runModal() == .OK, let url = panel.url {
            navigator.updateRoot(to: url)
        }
    }
}

// MARK: - Finder Sidebar
private struct FinderSidebarView: View {
    @ObservedObject var navigator: FileNavigatorViewModel
    let onSelectRoot: () -> Void
    let onClearRoot: () -> Void
    let onRefresh: () -> Void
    let onSelectURL: (URL) -> Void
    let onOpenFile: (URL) -> Void

    private var lastUpdatedText: String? {
        guard let root = navigator.rootURL else { return nil }
        let timestamp = navigator.lastUpdated(for: root) ?? navigator.lastRefreshed
        guard let timestamp else { return nil }
        return relativeTimestampText(timestamp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ライブラリ")
                        .font(.headline)
                    if let root = navigator.rootURL {
                        Text(root.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if let lastUpdatedText {
                        Text("最終更新: \(lastUpdatedText)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Menu {
                    Button("再読み込み", action: onRefresh)
                    Divider()
                    Button("フォルダを変更…", action: onSelectRoot)
                    Button("クリア", role: .destructive, action: onClearRoot)
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuStyle(BorderlessButtonMenuStyle())
            }
            .padding(.horizontal, 8)

            Divider()

            if navigator.isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                    Spacer()
                }
            } else if navigator.items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("フォルダ内に表示可能な項目がありません")
                        .font(.subheadline)
                    Button("フォルダを変更…", action: onSelectRoot)
                        .buttonStyle(LinkButtonStyle())
                }
                .padding(8)
            } else {
                List(selection: $navigator.selectedURL) {
                    OutlineGroup(navigator.items, children: \.children) { item in
                        FinderRow(item: item)
                            .tag(item.url)
                            .contentShape(Rectangle())
                            .contextMenu {
                                if item.isDirectory {
                                    Button("フォルダを表示") {
                                        onSelectURL(item.url)
                                    }
                                } else {
                                    Button("このファイルを開く") {
                                        onOpenFile(item.url)
                                    }
                                }
                            }
                    }
                }
                .listStyle(SidebarListStyle())
            }
        }
        .padding(.vertical, 12)
        .frame(minWidth: 260)
    }
}

// MARK: - Finder Detail
private struct FinderDetailView: View {
    @ObservedObject var navigator: FileNavigatorViewModel
    let onOpenFile: (URL) -> Void
    let onSelectRoot: () -> Void
    let onOpenDialog: () -> Void

    var body: some View {
        Group {
            if navigator.isLoading {
                VStack {
                    Spacer()
                    ProgressView("読み込み中…")
                        .progressViewStyle(CircularProgressViewStyle())
                    Spacer()
                }
            } else
            if let selected = navigator.selectedURL {
                if navigator.isDirectory(selected) {
                    DirectoryDetailView(
                        directoryURL: selected,
                        items: navigator.children(of: selected),
                        lastRefreshed: navigator.lastUpdated(for: selected),
                        onOpenFile: onOpenFile,
                        onSelectNode: { navigator.selectedURL = $0 },
                        onRefresh: { navigator.forceRefreshDirectory(at: selected) }
                    )
                } else if navigator.isSupportedFile(selected) {
                    FileSelectionPlaceholderView(selectedURL: selected)
                } else {
                    UnsupportedFileView(url: selected)
                }
            } else {
                FinderWelcomeView(
                    onChooseRoot: onSelectRoot,
                    onOpenDialog: onOpenDialog
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Directory Detail
private struct DirectoryDetailView: View {
    let directoryURL: URL
    let items: [FileNavigatorItem]
    let lastRefreshed: Date?
    let onOpenFile: (URL) -> Void
    let onSelectNode: (URL) -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(directoryURL.lastPathComponent)
                        .font(.title2)
                        .bold()
                    Text(directoryURL.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let lastRefreshed {
                        Text("最終更新: \(relativeTimestampText(lastRefreshed))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(action: onRefresh) {
                    Label("再読み込み", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("フォルダ内容を再スキャン")
            }

            if items.isEmpty {
                ContentUnavailableView(
                    "空のフォルダ",
                    systemImage: "folder",
                    description: Text("サポート対象のファイルやサブフォルダがありません。")
                )
            } else {
                List(items, id: \.id) { item in
                    FinderRow(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectNode(item.url)
                        }
                        .contextMenu {
                            if item.isDirectory {
                                Button("フォルダを表示") {
                                    onSelectNode(item.url)
                                }
                            } else {
                                Button("このファイルを開く") {
                                    onOpenFile(item.url)
                                }
                            }
                        }
                }
                .listStyle(.plain)
            }
            Spacer()
        }
        .padding(24)
    }
}

// MARK: - File Selection Placeholder
private struct FileSelectionPlaceholderView: View {
    let selectedURL: URL

    var body: some View {
        ContentUnavailableView(
            "ファイルを選択しました",
            systemImage: "doc.text",
            description: Text("右クリックメニューから開く操作を選択してください。\n\(selectedURL.lastPathComponent)")
        )
        .padding(32)
    }
}

// MARK: - Unsupported File View
private struct UnsupportedFileView: View {
    let url: URL

    var body: some View {
        ContentUnavailableView(
            "サポート外のファイル",
            systemImage: "xmark.octagon.fill",
            description: Text("\(url.lastPathComponent) は現在のビューアでは開けません。")
        )
        .padding(32)
    }
}

// MARK: - Finder Welcome
private struct FinderWelcomeView: View {
    let onChooseRoot: () -> Void
    let onOpenDialog: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "folder.fill.badge.plus")
                .font(.system(size: 72))
                .foregroundColor(.accentColor)

            Text("ライブラリを追加して開始")
                .font(.title)
                .bold()

            VStack(spacing: 16) {
                Button(action: onChooseRoot) {
                    InstructionCard(
                        icon: "folder",
                        title: "ライブラリフォルダを選択",
                        shortcut: "",
                        description: "選択したフォルダ内の画像・アーカイブを常時表示"
                    )
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: onOpenDialog) {
                    InstructionCard(
                        icon: "doc.fill",
                        title: "単体ファイルを開く",
                        shortcut: "⌘O",
                        description: "従来どおりファイル/フォルダを直接開く"
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }

            Text("またはファイルをドラッグ＆ドロップ")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(40)
    }
}

// MARK: - Finder Row
private struct FinderRow: View {
    let item: FileNavigatorItem

    var body: some View {
        Label {
            Text(item.name)
        } icon: {
            Image(systemName: item.isDirectory ? "folder" : "doc.richtext")
                .foregroundColor(item.isDirectory ? .accentColor : .secondary)
        }
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

// MARK: - Thumbnail Gallery View
struct ThumbnailGalleryView: View {
    @ObservedObject var viewModel: ReaderViewModel
    @Environment(\.presentationMode) var presentationMode

    private let columns = [
        GridItem(.adaptive(minimum: 90, maximum: 110), spacing: 20)
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.opacity(0.9)
                    .ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(0..<viewModel.totalPages, id: \.self) { pageIndex in
                                ThumbnailCard(
                                    pageIndex: pageIndex,
                                    viewModel: viewModel,
                                    isCurrentPage: pageIndex == viewModel.currentPageIndex
                                )
                                .id(pageIndex)
                            }
                        }
                        .padding(.horizontal, 30)
                        .padding(.vertical, 20)
                    }
                    .onAppear {
                        // 現在のページにスクロール
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo(viewModel.currentPageIndex, anchor: .center)
                        }
                    }
                }
            }
            .navigationTitle("Gallery")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button("Close") {
                        viewModel.toggleGallery()
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                }

                ToolbarItem(placement: .primaryAction) {
                    Text("Page \(viewModel.currentPageIndex + 1) of \(viewModel.totalPages)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Thumbnail Card
struct ThumbnailCard: View {
    let pageIndex: Int
    @ObservedObject var viewModel: ReaderViewModel
    let isCurrentPage: Bool

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCurrentPage ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.15))
                    .frame(width: 90, height: 130)

                Text("\(pageIndex + 1)")
                    .font(.title2)
                    .bold()
                    .foregroundColor(isCurrentPage ? .accentColor : .primary)

                if isCurrentPage {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 3)
                        .frame(width: 90, height: 130)
                }
            }
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }

            Text("Page \(pageIndex + 1)")
                .font(.caption)
                .foregroundColor(isCurrentPage ? .accentColor : .secondary)
                .fontWeight(isCurrentPage ? .bold : .regular)
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                viewModel.jumpToPage(pageIndex)
            }
        }
    }
}

// MARK: - Helper
private func relativeTimestampText(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}

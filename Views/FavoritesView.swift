//
//  FavoritesView.swift
//  Tosho
//
//  Created on 2025/09/27.
//

import SwiftUI

struct FavoritesView: View {
    @ObservedObject private var favoritesManager = FavoritesManager.shared
    @State private var selectedTab: FavoritesTab = .favorites
    @State private var searchText = ""

    enum FavoritesTab: String, CaseIterable {
        case favorites = "お気に入り"
        case frequent = "よく開く"
        case suggestions = "候補"
        case history = "履歴"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                HStack {
                    Text("ファイル管理")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

                    Button("履歴をクリア") {
                        showClearHistoryAlert()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }

                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("ファイル名で検索", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                }

                // Tab Selection
                Picker("タブ", selection: $selectedTab) {
                    ForEach(FavoritesTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredItems) { item in
                        FileHistoryCard(
                            item: item,
                            showFavoriteButton: selectedTab != .favorites,
                            onOpen: { openFile(item.url) },
                            onToggleFavorite: { toggleFavorite(item) },
                            onDismissSuggestion: selectedTab == .suggestions ? { dismissSuggestion(item) } : nil
                        )
                    }
                }
                .padding()
            }

            if filteredItems.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: emptyStateIcon)
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)

                    Text(emptyStateMessage)
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private var filteredItems: [FileHistoryItem] {
        let items: [FileHistoryItem]

        switch selectedTab {
        case .favorites:
            items = favoritesManager.getFavorites()
        case .frequent:
            items = favoritesManager.getFrequentlyAccessed()
        case .suggestions:
            items = favoritesManager.autoFavoriteSuggestions
        case .history:
            items = favoritesManager.fileHistory
        }

        if searchText.isEmpty {
            return items
        } else {
            return items.filter { item in
                item.fileName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private var emptyStateIcon: String {
        switch selectedTab {
        case .favorites: return "heart"
        case .frequent: return "clock"
        case .suggestions: return "lightbulb"
        case .history: return "doc.text"
        }
    }

    private var emptyStateMessage: String {
        switch selectedTab {
        case .favorites: return "お気に入りのファイルがありません"
        case .frequent: return "よく開くファイルがありません"
        case .suggestions: return "お気に入り候補がありません"
        case .history: return "ファイル履歴がありません"
        }
    }

    private func openFile(_ url: URL) {
        NotificationCenter.default.post(name: .openFile, object: url)
    }

    private func toggleFavorite(_ item: FileHistoryItem) {
        favoritesManager.setFavorite(item.url, favorite: !item.isFavorite)
    }

    private func dismissSuggestion(_ item: FileHistoryItem) {
        favoritesManager.dismissAutoFavoriteSuggestion(item.url)
    }

    private func showClearHistoryAlert() {
        let alert = NSAlert()
        alert.messageText = "履歴をクリアしますか？"
        alert.informativeText = "すべてのファイル履歴とお気に入り情報が削除されます。この操作は取り消せません。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "クリア")
        alert.addButton(withTitle: "キャンセル")

        if alert.runModal() == .alertFirstButtonReturn {
            favoritesManager.clearHistory()
        }
    }
}

struct FileHistoryCard: View {
    let item: FileHistoryItem
    let showFavoriteButton: Bool
    let onOpen: () -> Void
    let onToggleFavorite: () -> Void
    let onDismissSuggestion: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // File Icon
                Image(systemName: fileIcon)
                    .font(.title2)
                    .foregroundColor(iconColor)

                VStack(alignment: .leading, spacing: 4) {
                    // File Name
                    Text(item.fileName)
                        .font(.headline)
                        .lineLimit(1)

                    // Details
                    HStack(spacing: 12) {
                        Label(item.formattedAccessCount, systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Label(item.formattedLastAccessed, systemImage: "calendar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Action Buttons
                HStack(spacing: 8) {
                    if let dismissAction = onDismissSuggestion {
                        Button(action: dismissAction) {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .help("候補を却下")
                    }

                    if showFavoriteButton {
                        Button(action: onToggleFavorite) {
                            Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                                .foregroundColor(item.isFavorite ? .red : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(item.isFavorite ? "お気に入りから削除" : "お気に入りに追加")
                    }

                    Button(action: onOpen) {
                        Text("開く")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Auto-favorite suggestion banner
            if item.shouldBeAutoFavorite && !item.isFavorite {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.orange)

                    Text("このファイルをお気に入りに追加することをお勧めします")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Spacer()

                    Button("追加") {
                        onToggleFavorite()
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.orange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }

    private var fileIcon: String {
        let ext = item.url.pathExtension.lowercased()
        if ext == "zip" || ext == "cbz" {
            return "archivebox"
        } else {
            return "doc"
        }
    }

    private var iconColor: Color {
        let ext = item.url.pathExtension.lowercased()
        if ext == "zip" || ext == "cbz" {
            return .blue
        } else {
            return .gray
        }
    }

    private var backgroundColor: Color {
        if item.isFavorite {
            return Color.red.opacity(0.05)
        } else if item.shouldBeAutoFavorite {
            return Color.orange.opacity(0.05)
        } else {
            return Color(NSColor.controlBackgroundColor)
        }
    }

    private var borderColor: Color {
        if item.isFavorite {
            return Color.red.opacity(0.3)
        } else if item.shouldBeAutoFavorite {
            return Color.orange.opacity(0.3)
        } else {
            return Color.gray.opacity(0.2)
        }
    }
}

#Preview {
    FavoritesView()
        .frame(width: 700, height: 600)
}
//
//  RecentFilesView.swift
//  Tosho
//
//  Created on 2025/09/27.
//

import SwiftUI

struct RecentFilesView: View {
    @ObservedObject private var recentFilesManager = RecentFilesManager.shared
    @State private var searchText = ""
    @State private var showingNetworkHelp = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                HStack {
                    Text("最近開いたファイル")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

                    Button(action: {
                        showingNetworkHelp.toggle()
                    }) {
                        Image(systemName: "questionmark.circle")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .help("ネットワークドライブのヘルプ")

                    Button("すべてクリア") {
                        showClearAllAlert()
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
            }
            .padding()

            Divider()

            // Content
            if filteredFiles.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: searchText.isEmpty ? "clock" : "magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)

                    Text(searchText.isEmpty ? "最近開いたファイルがありません" : "該当するファイルが見つかりません")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    if searchText.isEmpty {
                        Text("ファイルを開くと、ここに履歴が表示されます")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredFiles) { item in
                            RecentFileCard(
                                item: item,
                                onOpen: { openRecentFile(item) },
                                onRemove: { removeRecentFile(item) }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .sheet(isPresented: $showingNetworkHelp) {
            NetworkDriveHelpView()
        }
    }

    private var filteredFiles: [RecentFileItem] {
        recentFilesManager.getFilteredFiles(searchText: searchText)
    }

    private func openRecentFile(_ item: RecentFileItem) {
        // ネットワークドライブの場合、アクセス可能性を事前チェック
        if isNetworkDrive(item.url) {
            checkNetworkFileAndOpen(item)
        } else {
            // ローカルファイルは直接オープン
            NotificationCenter.default.post(name: .recentFileOpened, object: item.url)
        }
    }

    private func checkNetworkFileAndOpen(_ item: RecentFileItem) {
        // バックグラウンドでネットワークファイルのアクセス性をチェック
        DispatchQueue.global(qos: .userInitiated).async {
            let isAccessible = FileManager.default.fileExists(atPath: item.url.path) &&
                              FileManager.default.isReadableFile(atPath: item.url.path)

            DispatchQueue.main.async {
                if isAccessible {
                    NotificationCenter.default.post(name: .recentFileOpened, object: item.url)
                } else {
                    showNetworkFileError(for: item)
                }
            }
        }
    }

    private func showNetworkFileError(for item: RecentFileItem) {
        let alert = NSAlert()
        alert.messageText = "ネットワークファイルにアクセスできません"
        alert.informativeText = """
        ファイル: \(item.fileName)
        パス: \(item.url.path)

        以下を確認してください：
        • ネットワークドライブがマウントされているか
        • ファイルが移動・削除されていないか
        • ネットワーク接続が正常か
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "再試行")
        alert.addButton(withTitle: "履歴から削除")
        alert.addButton(withTitle: "キャンセル")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            // 再試行
            checkNetworkFileAndOpen(item)
        case .alertSecondButtonReturn:
            // 履歴から削除
            removeRecentFile(item)
        default:
            // キャンセル
            break
        }
    }

    private func isNetworkDrive(_ url: URL) -> Bool {
        return url.scheme == "smb" || url.scheme == "afp" || url.path.contains("/Volumes/")
    }

    private func removeRecentFile(_ item: RecentFileItem) {
        recentFilesManager.removeRecentFile(item.url)
    }

    private func showClearAllAlert() {
        let alert = NSAlert()
        alert.messageText = "すべての履歴をクリアしますか？"
        alert.informativeText = "この操作は取り消せません。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "クリア")
        alert.addButton(withTitle: "キャンセル")

        if alert.runModal() == .alertFirstButtonReturn {
            recentFilesManager.clearAllRecentFiles()
        }
    }
}

struct RecentFileCard: View {
    let item: RecentFileItem
    let onOpen: () -> Void
    let onRemove: () -> Void

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

                    // File Path
                    Text(item.url.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)

                    // Details
                    HStack(spacing: 12) {
                        Label(item.formattedFileSize, systemImage: "doc")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Label(item.formattedLastOpened, systemImage: "calendar")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if isNetworkFile {
                            Label("ネットワーク", systemImage: "network")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }

                Spacer()

                // Action Buttons
                HStack(spacing: 8) {
                    Button(action: onRemove) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("履歴から削除")
                    .opacity(isHovered ? 1 : 0)

                    Button(action: onOpen) {
                        Text("開く")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                }
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

    private var isNetworkFile: Bool {
        item.url.scheme == "smb" || item.url.scheme == "afp" || item.url.path.contains("/Volumes/")
    }

    private var backgroundColor: Color {
        if isNetworkFile {
            return Color.blue.opacity(0.05)
        } else {
            return Color(NSColor.controlBackgroundColor)
        }
    }

    private var borderColor: Color {
        if isNetworkFile {
            return Color.blue.opacity(0.3)
        } else {
            return Color.gray.opacity(0.2)
        }
    }
}

struct NetworkDriveHelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ネットワークドライブのファイルについて")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 12) {
                HelpItem(
                    icon: "network",
                    title: "対応するネットワークプロトコル",
                    description: "SMB、AFP、その他Finderでマウント可能なネットワークドライブ"
                )

                HelpItem(
                    icon: "exclamationmark.triangle",
                    title: "注意事項",
                    description: "ネットワーク接続が不安定な場合、ファイルが開けない場合があります"
                )

                HelpItem(
                    icon: "arrow.clockwise",
                    title: "アクセスできない場合",
                    description: "ネットワークドライブの再マウントを試すか、履歴から削除してください"
                )

                HelpItem(
                    icon: "folder.badge.questionmark",
                    title: "ファイルパスの例",
                    description: "/Volumes/ShareName/folder/file.zip"
                )
            }

            Spacer()

            HStack {
                Spacer()
                Button("閉じる") {
                    // シートを閉じる
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding()
        .frame(width: 400, height: 300)
    }
}

struct HelpItem: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    RecentFilesView()
        .frame(width: 700, height: 600)
}
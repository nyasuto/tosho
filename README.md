# Tosho (図書) - Mac用最強漫画ビューワー

<div align="center">
  <h3>📚 Tosho - Beautiful Manga Reader for macOS</h3>
  <p>洗練されたデザインと高速な動作を実現する、Mac専用の漫画リーダー</p>
</div>

## プロジェクト概要
**Tosho**は、macOS専用のネイティブ漫画ビューワーアプリケーション。日本語の「図書」から名付けられた、シンプルで美しい読書体験を提供する個人用ツール。

### なぜTosho？
- 📖 **図書** - 本を意味するシンプルで覚えやすい名前
- 🍎 **Mac Native** - SwiftUIで構築された真のmacOSアプリ
- ⚡ **高速** - ネイティブパフォーマンスで快適な読書体験
- 🎨 **美しい** - macOSのデザイン言語に完全準拠

## 技術スタック
- **言語**: Swift 5.9+
- **UI Framework**: SwiftUI
- **最小対応OS**: macOS 14.0 (Sonoma)
- **アーキテクチャ**: MVVM
- **開発ツール**: Xcode 15.0+
- **Bundle ID**: com.personal.tosho

## コア機能要件

### Phase 1: MVP（最小限の動作）
- [ ] 単一画像ファイルの表示（JPEG, PNG, WEBP）
- [ ] 基本的なウィンドウ管理
- [ ] キーボードでのページ送り（←→キー）
- [ ] フォルダ内画像の連続表示

### Phase 2: 基本機能
- [ ] ZIP/CBZ形式の読み込み
- [ ] RAR/CBR形式の読み込み
- [ ] 見開き表示モード（2ページ表示）
- [ ] 右綴じ/左綴じ切り替え
- [ ] トラックパッドジェスチャー対応
- [ ] フルスクリーン表示

### Phase 3: UI/UX改善
- [ ] サムネイル一覧表示（Toshoギャラリー）
- [ ] ページジャンプ機能
- [ ] ツールバーのカスタマイズ
- [ ] 読書進捗の保存/復元
- [ ] 最近開いたファイルの履歴（Tosho履歴）

### Phase 4: 高度な機能
- [ ] Toshoライブラリ（本棚機能）
- [ ] シリーズ/巻数での整理
- [ ] ブックマーク機能
- [ ] メタデータ編集
- [ ] 画像補正（明度/コントラスト）

## ファイル構造
```
Tosho/
├── Tosho.xcodeproj
├── Tosho/
│   ├── App/
│   │   ├── ToshoApp.swift
│   │   └── Info.plist
│   ├── Views/
│   │   ├── ContentView.swift
│   │   ├── ReaderView.swift
│   │   ├── ThumbnailView.swift
│   │   ├── LibraryView.swift
│   │   └── SettingsView.swift
│   ├── ViewModels/
│   │   ├── ReaderViewModel.swift
│   │   └── LibraryViewModel.swift
│   ├── Models/
│   │   ├── ToshoDocument.swift
│   │   ├── Page.swift
│   │   └── ReadingProgress.swift
│   ├── Services/
│   │   ├── FileLoader.swift
│   │   ├── ImageCache.swift
│   │   └── ArchiveExtractor.swift
│   ├── Resources/
│   │   ├── Assets.xcassets
│   │   └── Tosho.iconset/
│   └── Localization/
│       ├── ja.lproj/
│       └── en.lproj/
├── Tests/
│   └── ToshoTests/
└── README.md
```

## UI/UXガイドライン

### アプリケーションアイデンティティ
- **アプリ名**: Tosho
- **アイコン**: 開いた本または日本の書物をモチーフにしたデザイン
- **カラーテーマ**: システムアクセントカラー準拠
- **フォント**: システムフォント（SF Pro）

### ウィンドウ構成
- シングルウィンドウアプリケーション
- 最小サイズ: 800x600
- デフォルトサイズ: 1200x900
- ウィンドウタイトル: "Tosho - [ファイル名]"

### 操作体系
| 操作 | キーボード | トラックパッド | メニュー |
|------|------------|----------------|----------|
| 次のページ | → / Space | 左スワイプ | View > Next Page |
| 前のページ | ← | 右スワイプ | View > Previous Page |
| 見開き切替 | D | ダブルタップ | View > Double Page |
| フルスクリーン | Cmd+F | - | View > Full Screen |
| Toshoギャラリー | Cmd+T | 3本指ピンチ | View > Gallery |
| Toshoライブラリ | Cmd+L | - | Window > Library |

### デザイン原則
- macOSのHuman Interface Guidelinesに準拠
- ダークモード完全対応
- 読書に集中できるミニマルなUI
- 必要な時だけ現れるコントロール

## パフォーマンス目標
- 画像表示: 100ms以内
- ページ切り替え: 50ms以内
- ZIP展開: 1000ページで5秒以内
- メモリ使用: 最大500MB（キャッシュ込み）
- アプリ起動: 2秒以内

## 開発手順

### ビルド＆実行
```bash
# コマンドラインビルド
xcodebuild -scheme Tosho build

# または Xcode で Cmd+R
```

### アイコン作成
```bash
# Tosho.iconsetフォルダを作成し、以下のサイズを用意
# icon_16x16.png
# icon_16x16@2x.png
# icon_32x32.png
# icon_32x32@2x.png
# icon_128x128.png
# icon_128x128@2x.png
# icon_256x256.png
# icon_256x256@2x.png
# icon_512x512.png
# icon_512x512@2x.png
```

## テストデータ
- `Resources/SampleImages/`: テスト用画像
- `Resources/SampleArchives/`: ZIP/RARサンプル
- 異なる解像度とアスペクト比の画像を用意

## Toshoの特徴的な機能（将来構想）

### Toshoライブラリ
- 本棚のような美しいビジュアルで漫画を管理
- カバーアートの自動取得
- シリーズごとの自動グループ化

### Tosho Sync（Phase 5）
- iCloud経由での読書進捗同期
- お気に入りとブックマークの同期

### Tosho Reader Mode
- 縦スクロール対応（Webtoon形式）
- 自動ページめくり
- 読書速度に合わせた調整

## 注意事項
- 著作権保護されたコンテンツの扱いに注意
- 個人使用を前提とした設計
- App Store配布は想定しない
- 「Tosho」の商標登録状況は要確認

## 参考リソース
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/macos)
- [UnrarKit](https://github.com/abbeycode/UnrarKit) - RAR解凍用
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) - ZIP処理用

## コントリビューション
個人プロジェクトのため、現在は外部コントリビューションを受け付けていません。

## ライセンス
個人使用限定

---

**Tosho** - 洗練された読書体験をあなたのMacに  
最終更新: 2025年1月
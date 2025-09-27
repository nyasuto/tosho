//
//  ReaderView.swift
//  Tosho
//
//  Created on 2025/09/27.
//

import SwiftUI

struct ReaderView: View {
    let fileURL: URL?
    @ObservedObject var viewModel: ReaderViewModel
    @State private var currentZoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    // Legacy initializer for existing ContentView
    init(fileURL: URL) {
        self.fileURL = fileURL
        self.viewModel = ReaderViewModel()
    }

    // New initializer for DocumentReaderView
    init(viewModel: ReaderViewModel) {
        self.fileURL = nil
        self.viewModel = viewModel
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                if viewModel.shouldShowDoublePages {
                    // 見開きモード（2ページ表示）
                    HStack(spacing: 0) {
                        // 右綴じの場合、ページ順序を反転
                        if viewModel.readingSettings.readingDirection.isRightToLeft {
                            // 右綴じ：右ページ（secondImage）→左ページ（currentImage）
                            if let secondImage = viewModel.secondImage {
                                Image(nsImage: secondImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .scaleEffect(currentZoom)
                                    .offset(offset)
                                    .gesture(magnificationGesture)
                                    .gesture(dragGesture)
                                    .onTapGesture(count: 2) {
                                        resetZoom()
                                    }
                            }

                            if let image = viewModel.currentImage {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .scaleEffect(currentZoom)
                                    .offset(offset)
                                    .gesture(magnificationGesture)
                                    .gesture(dragGesture)
                                    .onTapGesture(count: 2) {
                                        resetZoom()
                                    }
                            }
                        } else {
                            // 左綴じ：左ページ（currentImage）→右ページ（secondImage）
                            if let image = viewModel.currentImage {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .scaleEffect(currentZoom)
                                    .offset(offset)
                                    .gesture(magnificationGesture)
                                    .gesture(dragGesture)
                                    .onTapGesture(count: 2) {
                                        resetZoom()
                                    }
                            }

                            if let secondImage = viewModel.secondImage {
                                Image(nsImage: secondImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .scaleEffect(currentZoom)
                                    .offset(offset)
                                    .gesture(magnificationGesture)
                                    .gesture(dragGesture)
                                    .onTapGesture(count: 2) {
                                        resetZoom()
                                    }
                            }
                        }
                    }
                } else if let image = viewModel.currentImage {
                    // 単ページモード
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(currentZoom)
                        .offset(offset)
                        .gesture(magnificationGesture)
                        .gesture(dragGesture)
                        .onTapGesture(count: 2) {
                            resetZoom()
                        }
                } else if viewModel.isLoading {
                    VStack(spacing: 16) {
                        if viewModel.loadingProgress > 0 {
                            // 全画像プリロード時の進捗表示
                            VStack(spacing: 8) {
                                Text("全画像を読み込み中...")
                                    .font(.title3)
                                    .foregroundColor(.white)

                                ProgressView(value: viewModel.loadingProgress, total: 1.0)
                                    .progressViewStyle(LinearProgressViewStyle())
                                    .frame(width: 200)

                                Text("\(Int(viewModel.loadingProgress * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        } else {
                            // 通常の読み込み表示
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .foregroundColor(.white)
                                .scaleEffect(1.5)
                        }
                    }
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.yellow)

                        Text("Error Loading Image")
                            .font(.title2)
                            .foregroundColor(.white)

                        Text(error)
                            .font(.body)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                // Navigation Controls Overlay
                HStack {
                    if viewModel.hasPreviousPage && !viewModel.isLoading {
                        Button(action: { viewModel.previousPage() }) {
                            Image(systemName: "chevron.left")
                                .font(.title)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.leading)
                    }

                    Spacer()

                    if viewModel.hasNextPage && !viewModel.isLoading {
                        Button(action: { viewModel.nextPage() }) {
                            Image(systemName: "chevron.right")
                                .font(.title)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.trailing)
                    }
                }
                .opacity(viewModel.showControls ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: viewModel.showControls)

                // Page Indicator
                VStack {
                    Spacer()
                    if viewModel.totalPages > 0 {
                        HStack(spacing: 12) {
                            // ページ番号表示
                            if viewModel.shouldShowDoublePages {
                                let endPage = min(viewModel.currentPageIndex + 2, viewModel.totalPages)
                                Text("\(viewModel.currentPageIndex + 1)-\(endPage) / \(viewModel.totalPages)")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            } else {
                                Text("\(viewModel.currentPageIndex + 1) / \(viewModel.totalPages)")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }

                            // 見開きモード表示インジケーター
                            if viewModel.isDoublePageMode {
                                Image(systemName: "rectangle.split.2x1")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }

                            // 綴じ方向表示インジケーター
                            Text(viewModel.readingSettings.readingDirection.isRightToLeft ? "右綴じ" : "左綴じ")
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.3))
                                .cornerRadius(3)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                        .padding(.bottom, 20)
                        .opacity(viewModel.showControls ? 1 : 0)
                        .animation(.easeInOut(duration: 0.3), value: viewModel.showControls)
                    }
                }
                
                // ウィンドウスコープの非表示キーボードショートカットボタン
                VStack {
                    Button("Next Page") {
                        viewModel.nextPage()
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    .hidden()
                    
                    Button("Previous Page") {
                        viewModel.previousPage()
                    }
                    .keyboardShortcut(.space, modifiers: .shift)
                    .hidden()
                    
                    Button("Adjust Forward") {
                        viewModel.adjustPageForward()
                    }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .hidden()
                    
                    Button("Adjust Backward") {
                        viewModel.adjustPageBackward()
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .hidden()
                    
                    Button("Toggle Double Page") {
                        viewModel.toggleDoublePageMode()
                    }
                    .keyboardShortcut("d", modifiers: [])
                    .hidden()
                    
                    Button("Toggle Reading Direction") {
                        viewModel.toggleReadingDirection()
                    }
                    .keyboardShortcut("r", modifiers: [])
                    .hidden()
                    
                    Button("Toggle Gallery") {
                        viewModel.toggleGallery()
                    }
                    .keyboardShortcut("t", modifiers: .command)
                    .hidden()
                }
            }
            .onAppear {
                if let fileURL = fileURL {
                    viewModel.loadContent(from: fileURL)
                }
            }
            .onHover { hovering in
                viewModel.showControls = hovering
            }
            .focusable(true)
            .sheet(isPresented: $viewModel.showGallery) {
                ThumbnailGalleryView(viewModel: viewModel)
            }
        }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                currentZoom = value
            }
            .onEnded { value in
                if value < 1.0 {
                    currentZoom = 1.0
                } else if value > 3.0 {
                    currentZoom = 3.0
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if currentZoom > 1.0 {
                    offset = CGSize(
                        width: value.translation.width,
                        height: value.translation.height
                    )
                }
            }
    }

    private func resetZoom() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentZoom = 1.0
            offset = .zero
        }
    }

    // キーボードショートカットの処理はCommands（ToshoApp.swift）に移動

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .nextPage,
            object: nil,
            queue: .main
        ) { _ in
            viewModel.nextPage()
        }

        NotificationCenter.default.addObserver(
            forName: .previousPage,
            object: nil,
            queue: .main
        ) { _ in
            viewModel.previousPage()
        }

        NotificationCenter.default.addObserver(
            forName: .toggleDoublePage,
            object: nil,
            queue: .main
        ) { _ in
            viewModel.toggleDoublePageMode()
        }

        NotificationCenter.default.addObserver(
            forName: .toggleReadingDirection,
            object: nil,
            queue: .main
        ) { _ in
            viewModel.toggleReadingDirection()
        }

        NotificationCenter.default.addObserver(
            forName: .toggleGallery,
            object: nil,
            queue: .main
        ) { _ in
            viewModel.toggleGallery()
        }

        NotificationCenter.default.addObserver(
            forName: .adjustPageForward,
            object: nil,
            queue: .main
        ) { _ in
            viewModel.adjustPageForward()
        }

        NotificationCenter.default.addObserver(
            forName: .adjustPageBackward,
            object: nil,
            queue: .main
        ) { _ in
            viewModel.adjustPageBackward()
        }
    }
}

// MARK: - Preview
struct ReaderView_Previews: PreviewProvider {
    static var previews: some View {
        ReaderView(fileURL: URL(fileURLWithPath: "/path/to/image.jpg"))
            .frame(width: 1200, height: 900)
    }
}
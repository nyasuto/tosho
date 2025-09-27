//
//  ReaderView.swift
//  Tosho
//
//  Created on 2025/09/27.
//

import SwiftUI

struct ReaderView: View {
    let fileURL: URL
    @StateObject private var viewModel = ReaderViewModel()
    @State private var currentZoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero

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
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .foregroundColor(.white)
                        .scaleEffect(1.5)
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
                    if viewModel.hasPreviousPage {
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

                    if viewModel.hasNextPage {
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
            }
            .onAppear {
                viewModel.loadContent(from: fileURL)
                setupNotificationObservers()
            }
            .onHover { hovering in
                viewModel.showControls = hovering
            }
            .focusable(true)
            .onKeyPress { keyPress in
                handleKeyPress(keyPress)
                return .handled
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

    private func handleKeyPress(_ keyPress: KeyPress) {
        switch keyPress.key {
        case .rightArrow, .space:
            if viewModel.readingSettings.readingDirection.isRightToLeft {
                // 右綴じ：右矢印は戻る
                viewModel.previousPage()
            } else {
                // 左綴じ：右矢印は進む
                viewModel.nextPage()
            }
        case .leftArrow:
            if viewModel.readingSettings.readingDirection.isRightToLeft {
                // 右綴じ：左矢印は進む
                viewModel.nextPage()
            } else {
                // 左綴じ：左矢印は戻る
                viewModel.previousPage()
            }
        case .init(.init("d")), .init(.init("D")):
            viewModel.toggleDoublePageMode()
            resetZoom()
        case .init(.init("r")), .init(.init("R")):
            viewModel.toggleReadingDirection()
        default:
            break
        }
    }

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
    }
}

// MARK: - Preview
struct ReaderView_Previews: PreviewProvider {
    static var previews: some View {
        ReaderView(fileURL: URL(fileURLWithPath: "/path/to/image.jpg"))
            .frame(width: 1200, height: 900)
    }
}
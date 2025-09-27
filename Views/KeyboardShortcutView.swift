//
//  KeyboardShortcutView.swift
//  Tosho
//
//  Created on 2025/09/27.
//

import SwiftUI

struct KeyboardShortcutView: ViewModifier {
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onToggleDoublePageMode: () -> Void
    let onToggleReadingDirection: () -> Void

    func body(content: Content) -> some View {
        content
            .background(
                // スペースキー - 進む
                Button("") {
                    onNext()
                }
                .keyboardShortcut(" ", modifiers: [])
                .hidden()
            )
            .background(
                // Shift+スペース - 戻る
                Button("") {
                    onPrevious()
                }
                .keyboardShortcut(" ", modifiers: .shift)
                .hidden()
            )
            .background(
                // 右矢印 - 状況により異なる（別途処理）
                Button("") {
                    // ReaderViewで処理
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .hidden()
            )
            .background(
                // 左矢印 - 状況により異なる（別途処理）
                Button("") {
                    // ReaderViewで処理
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .hidden()
            )
            .background(
                // D - 見開きモード切り替え
                Button("") {
                    onToggleDoublePageMode()
                }
                .keyboardShortcut("d", modifiers: [])
                .hidden()
            )
            .background(
                // R - 読み方向切り替え
                Button("") {
                    onToggleReadingDirection()
                }
                .keyboardShortcut("r", modifiers: [])
                .hidden()
            )
    }
}

extension View {
    func keyboardShortcuts(
        onNext: @escaping () -> Void,
        onPrevious: @escaping () -> Void,
        onToggleDoublePageMode: @escaping () -> Void,
        onToggleReadingDirection: @escaping () -> Void
    ) -> some View {
        modifier(KeyboardShortcutView(
            onNext: onNext,
            onPrevious: onPrevious,
            onToggleDoublePageMode: onToggleDoublePageMode,
            onToggleReadingDirection: onToggleReadingDirection
        ))
    }
}
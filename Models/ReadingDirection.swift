//
//  ReadingDirection.swift
//  Tosho
//
//  Created on 2025/09/27.
//

import Foundation

enum ReadingDirection: String, CaseIterable {
    case leftToRight  // 左から右（西洋式）
    case rightToLeft  // 右から左（日本式）

    var displayName: String {
        switch self {
        case .leftToRight:
            return "左綴じ (西洋式)"
        case .rightToLeft:
            return "右綴じ (日本式)"
        }
    }

    var isRightToLeft: Bool {
        return self == .rightToLeft
    }

    var isLeftToRight: Bool {
        return self == .leftToRight
    }
}

class ReadingSettings: ObservableObject {
    @Published var readingDirection: ReadingDirection {
        didSet {
            saveSettings()
        }
    }

    private let userDefaults = UserDefaults.standard
    private let readingDirectionKey = "ToshoReadingDirection"

    init() {
        // 保存された設定を読み込み、デフォルトは左綴じ（西洋式）
        let savedDirection = userDefaults.string(forKey: readingDirectionKey) ?? ReadingDirection.leftToRight.rawValue
        self.readingDirection = ReadingDirection(rawValue: savedDirection) ?? .leftToRight
    }

    private func saveSettings() {
        userDefaults.set(readingDirection.rawValue, forKey: readingDirectionKey)
    }

    func toggleDirection() {
        readingDirection = readingDirection == .leftToRight ? .rightToLeft : .leftToRight
    }
}

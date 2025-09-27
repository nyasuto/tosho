//
//  DebugLogger.swift
//  Tosho
//
//  Created on 2025/09/27.
//

import Foundation
import os.log

class DebugLogger {
    static let shared = DebugLogger()
    private let logger = Logger(subsystem: "com.personal.tosho", category: "Debug")

    private init() {}

    func log(_ message: String, category: String = "General") {
        let timestamp = DateFormatter.timestamp.string(from: Date())
        let logMessage = "[\(timestamp)] [\(category)] \(message)"

        // Console output for debugging
        print(logMessage)

        // System logging
        logger.info("\(logMessage)")
    }

    func logError(_ error: Error, category: String = "Error", context: String = "") {
        let contextInfo = context.isEmpty ? "" : " Context: \(context)"
        let message = "ERROR: \(error.localizedDescription)\(contextInfo)"
        log(message, category: category)
    }

    func logArchiveOperation(_ operation: String, file: String? = nil, details: String? = nil) {
        var message = "Archive Operation: \(operation)"
        if let file = file {
            message += " File: \(file)"
        }
        if let details = details {
            message += " Details: \(details)"
        }
        log(message, category: "Archive")
    }
}

extension DateFormatter {
    static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
}
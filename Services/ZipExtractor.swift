//
//  ZipExtractor.swift
//  Tosho
//
//  Created on 2025/09/27.
//

import Foundation
import AppKit

// MARK: - ZipExtraction Error Types
enum ZipExtractionError: Error, LocalizedError {
    case unzipNotFound
    case processLaunchFailed
    case nonZeroExit(Int32, String)
    case zeroLengthData(String)
    case memoryLimitExceeded(Int)
    case timeout
    case encryptedArchive

    var errorDescription: String? {
        switch self {
        case .unzipNotFound:
            return "System unzip command not found"
        case .processLaunchFailed:
            return "Failed to launch unzip process"
        case .nonZeroExit(let code, let message):
            return "Unzip failed with exit code \(code): \(message)"
        case .zeroLengthData(let member):
            return "No data extracted for member: \(member)"
        case .memoryLimitExceeded(let size):
            return "Memory limit exceeded: \(size) bytes"
        case .timeout:
            return "Extraction timeout"
        case .encryptedArchive:
            return "Encrypted archive not supported"
        }
    }
}

// MARK: - Memory-based ZIP Extractor
struct ZipExtractor {

    // MARK: - Configuration
    private static let defaultReadChunkSize = 128 * 1024  // 128KB
    private static let defaultMaxSizePerImage = 200 * 1024 * 1024  // 200MB
    private static let defaultTimeout: TimeInterval = 10.0  // 10 seconds

    // MARK: - Main extraction method
    /// Extract a specific member from ZIP archive directly into memory
    /// - Parameters:
    ///   - member: File name within the archive
    ///   - archiveURL: URL to the ZIP/CBZ file
    ///   - readChunk: Size of chunks to read (default: 128KB)
    ///   - maxSize: Maximum size limit per file (default: 200MB)
    ///   - timeout: Timeout for extraction process (default: 10s)
    /// - Returns: Data containing the extracted file content
    /// - Throws: ZipExtractionError for various failure cases
    static func data(forMember member: String,
                     inArchive archiveURL: URL,
                     readChunk: Int = defaultReadChunkSize,
                     maxSize: Int = defaultMaxSizePerImage,
                     timeout: TimeInterval = defaultTimeout) throws -> Data {

        DebugLogger.shared.logArchiveOperation("Starting memory extraction",
                                               file: archiveURL.lastPathComponent,
                                               details: "Member: \(member)")

        // 1. Verify that /usr/bin/unzip exists
        let unzipURL = URL(fileURLWithPath: "/usr/bin/unzip")
        guard FileManager.default.isExecutableFile(atPath: unzipURL.path) else {
            DebugLogger.shared.logError(ZipExtractionError.unzipNotFound,
                                        context: "Unzip not found at \(unzipURL.path)")
            throw ZipExtractionError.unzipNotFound
        }

        // 2. Configure the Process
        let process = Process()
        process.executableURL = unzipURL
        process.arguments = ["-p", archiveURL.path, member]

        // 3. Capture stdout + stderr
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // 4. Setup timeout handling
        let timeoutWorkItem = DispatchWorkItem {
            if process.isRunning {
                DebugLogger.shared.logArchiveOperation("Process timeout, terminating",
                                                       file: archiveURL.lastPathComponent,
                                                       details: "Member: \(member)")
                process.terminate()
            }
        }

        do {
            // 5. Launch process
            try process.run()
            DebugLogger.shared.logArchiveOperation("Process launched successfully",
                                                   file: archiveURL.lastPathComponent)

            // Start timeout timer
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

            // 6. Read in streaming chunks to avoid buffering entire file in RAM
            let handle = outPipe.fileHandleForReading
            var buffer = Data()
            var totalBytesRead = 0

            while true {
                let chunk = try handle.read(upToCount: readChunk) ?? Data()
                if chunk.isEmpty { break }

                totalBytesRead += chunk.count

                // Check memory limit
                if totalBytesRead > maxSize {
                    process.terminate()
                    timeoutWorkItem.cancel()
                    DebugLogger.shared.logArchiveOperation("Memory limit exceeded",
                                                           file: archiveURL.lastPathComponent,
                                                           details: "Size: \(totalBytesRead) > \(maxSize)")
                    throw ZipExtractionError.memoryLimitExceeded(totalBytesRead)
                }

                buffer.append(chunk)
            }

            // 7. Wait for process completion and check results
            process.waitUntilExit()
            timeoutWorkItem.cancel()

            let exitCode = process.terminationStatus
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errData, encoding: .utf8) ?? ""

            DebugLogger.shared.logArchiveOperation("Process completed",
                                                   file: archiveURL.lastPathComponent,
                                                   details: "Exit code: \(exitCode), Data size: \(buffer.count)")

            // Handle different exit codes
            switch exitCode {
            case 0:
                // Success
                break
            case 3:
                // Encrypted archive
                DebugLogger.shared.logArchiveOperation("Encrypted archive detected",
                                                       file: archiveURL.lastPathComponent)
                throw ZipExtractionError.encryptedArchive
            default:
                // Other errors
                DebugLogger.shared.logArchiveOperation("Unzip failed",
                                                       file: archiveURL.lastPathComponent,
                                                       details: "Exit: \(exitCode), Error: \(errorMessage)")
                throw ZipExtractionError.nonZeroExit(exitCode, errorMessage)
            }

            // 8. Validate extracted data
            guard !buffer.isEmpty else {
                DebugLogger.shared.logArchiveOperation("Zero length data extracted",
                                                       file: archiveURL.lastPathComponent,
                                                       details: "Member: \(member)")
                throw ZipExtractionError.zeroLengthData(member)
            }

            DebugLogger.shared.logArchiveOperation("Memory extraction completed successfully",
                                                   file: archiveURL.lastPathComponent,
                                                   details: "Extracted \(buffer.count) bytes")
            return buffer

        } catch let error as ZipExtractionError {
            timeoutWorkItem.cancel()
            throw error
        } catch {
            timeoutWorkItem.cancel()
            DebugLogger.shared.logError(error,
                                        context: "Process launch failed for \(archiveURL.lastPathComponent)")
            throw ZipExtractionError.processLaunchFailed
        }
    }

    // MARK: - Convenience method for NSImage
    /// Extract a specific member and convert to NSImage
    /// - Parameters:
    ///   - member: File name within the archive
    ///   - archiveURL: URL to the ZIP/CBZ file
    /// - Returns: NSImage instance or nil if conversion fails
    /// - Throws: ZipExtractionError for extraction failures
    static func image(forMember member: String, inArchive archiveURL: URL) throws -> NSImage? {
        let data = try self.data(forMember: member, inArchive: archiveURL)
        return NSImage(data: data)
    }

    // MARK: - Validation helpers
    /// Check if a file is supported for memory extraction
    /// - Parameter url: Archive URL to check
    /// - Returns: true if supported (ZIP/CBZ)
    static func isSupported(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "zip" || ext == "cbz"
    }
}
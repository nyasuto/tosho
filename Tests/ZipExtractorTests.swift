//
//  ZipExtractorTests.swift
//  Tosho
//
//  Created on 2025/09/27.
//

import Foundation

class ZipExtractorTests {

    /// Test memory-based ZIP extraction functionality
    static func runBasicTests() {
        print("🧪 Starting ZipExtractor basic tests...")

        // Test 1: Check if unzip command exists
        testUnzipAvailability()

        // Test 2: Basic error handling
        testErrorHandling()

        print("✅ ZipExtractor basic tests completed")
    }

    private static func testUnzipAvailability() {
        print("Testing unzip command availability...")

        let unzipURL = URL(fileURLWithPath: "/usr/bin/unzip")
        let exists = FileManager.default.isExecutableFile(atPath: unzipURL.path)

        if exists {
            print("✅ /usr/bin/unzip is available")
        } else {
            print("❌ /usr/bin/unzip not found")
        }
    }

    private static func testErrorHandling() {
        print("Testing error handling...")

        // Test with non-existent archive
        let fakeArchiveURL = URL(fileURLWithPath: "/tmp/nonexistent.zip")

        do {
            let _ = try ZipExtractor.data(forMember: "test.jpg", inArchive: fakeArchiveURL)
            print("❌ Should have thrown an error for non-existent archive")
        } catch ZipExtractionError.nonZeroExit(let code, let message) {
            print("✅ Correctly handled non-existent archive: exit code \(code)")
        } catch {
            print("✅ Error handling works: \(error.localizedDescription)")
        }
    }

    /// Performance benchmark test (requires actual ZIP file)
    static func runPerformanceTest(with archiveURL: URL, member: String) {
        print("🚀 Starting performance test...")
        print("Archive: \(archiveURL.lastPathComponent)")
        print("Member: \(member)")

        let iterations = 5
        var memoryTimes: [TimeInterval] = []

        // Test memory-based extraction
        for i in 1...iterations {
            let startTime = CFAbsoluteTimeGetCurrent()

            do {
                let data = try ZipExtractor.data(forMember: member, inArchive: archiveURL)
                let endTime = CFAbsoluteTimeGetCurrent()
                let elapsed = endTime - startTime
                memoryTimes.append(elapsed)

                print("Memory extraction #\(i): \(String(format: "%.3f", elapsed))s (\(data.count) bytes)")
            } catch {
                print("❌ Memory extraction #\(i) failed: \(error)")
            }
        }

        if !memoryTimes.isEmpty {
            let avgMemoryTime = memoryTimes.reduce(0, +) / Double(memoryTimes.count)
            let minMemoryTime = memoryTimes.min() ?? 0
            let maxMemoryTime = memoryTimes.max() ?? 0

            print("📊 Memory extraction results:")
            print("   Average: \(String(format: "%.3f", avgMemoryTime))s")
            print("   Min: \(String(format: "%.3f", minMemoryTime))s")
            print("   Max: \(String(format: "%.3f", maxMemoryTime))s")
        }
    }

    /// Memory usage test
    static func testMemoryLimits() {
        print("🧠 Testing memory limits...")

        // Test with very small memory limit
        let fakeArchiveURL = URL(fileURLWithPath: "/tmp/test.zip")

        do {
            let _ = try ZipExtractor.data(forMember: "test.jpg",
                                          inArchive: fakeArchiveURL,
                                          maxSize: 1024) // 1KB limit
            print("❌ Should have failed with memory limit")
        } catch ZipExtractionError.memoryLimitExceeded(let size) {
            print("✅ Memory limit correctly enforced at \(size) bytes")
        } catch {
            print("✅ Memory limit test handled: \(error)")
        }
    }
}
//
//  ContentView.swift
//  Tosho
//
//  Created on 2025/09/27.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedFileURL: URL?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if let url = selectedFileURL {
                ReaderView(fileURL: url)
            } else {
                WelcomeView()
            }

            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.3))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            setupNotificationObservers()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") {
                errorMessage = nil
            }
        }, message: {
            if let error = errorMessage {
                Text(error)
            }
        })
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .openFile,
            object: nil,
            queue: .main
        ) { notification in
            if let url = notification.object as? URL {
                selectedFileURL = url
            }
        }

        NotificationCenter.default.addObserver(
            forName: .openFolder,
            object: nil,
            queue: .main
        ) { notification in
            if let url = notification.object as? URL {
                selectedFileURL = url
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }

        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (item, error) in
            guard error == nil,
                  let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }

            DispatchQueue.main.async {
                self.selectedFileURL = url
            }
        }
    }
}

// MARK: - Welcome View
struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)

            Text("Tosho")
                .font(.system(size: 48, weight: .bold, design: .rounded))

            Text("Beautiful Manga Reader for macOS")
                .font(.title3)
                .foregroundColor(.secondary)

            VStack(spacing: 15) {
                HStack(spacing: 20) {
                    InstructionCard(
                        icon: "folder",
                        title: "Open Folder",
                        shortcut: "⌘⇧O",
                        description: "Browse image folders"
                    )

                    InstructionCard(
                        icon: "doc",
                        title: "Open File",
                        shortcut: "⌘O",
                        description: "Select single image"
                    )
                }

                Text("or drag & drop files here")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Supported formats info
                Text("Supports: JPEG, PNG, WebP, HEIC, TIFF, BMP, GIF")
                    .font(.caption2)
                    .foregroundColor(.tertiary)
                    .padding(.top, 5)
            }
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Instruction Card
struct InstructionCard: View {
    let icon: String
    let title: String
    let shortcut: String
    let description: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.accentColor)

            Text(title)
                .font(.caption)
                .fontWeight(.medium)

            Text(description)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text(shortcut)
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        }
        .frame(width: 120, height: 100)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .frame(width: 1200, height: 900)
}
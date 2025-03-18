//
//  ContentView.swift
//  EchoWrite
//
//  Created by Ajinkya  on 02/01/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedDirectory: URL? = nil
    @State private var directoryPath: String = ""
    @State private var selectedFile: String? = nil
    @State private var isDropTargeted = false
    
    @StateObject private var transcriptionState = TranscriptionManager.shared.state
    private let transcriptionManager = TranscriptionManager.shared
    
    @StateObject private var directoryMonitor: DirectoryMonitor = {
        DirectoryMonitor { newFile in
            ContentView.transcribeNewFile(newFile)
        }
    }()
    
    var body: some View {
        VStack(spacing: 0) {
            // Directory Selection Header
            HStack(spacing: 10) {
                TextField("Selected Directory", text: $directoryPath)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(maxWidth: .infinity)
                    .disabled(true)
                
                Button(action: selectDirectory) {
                    Text(selectedDirectory != nil ? "Change Directory" : "Choose Directory")
                        .frame(width: 120)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            HSplitView {
                // Left sidebar with files list
                VStack(spacing: 0) {
                    Text("Files")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.1))
                    
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(directoryMonitor.files, id: \.lastPathComponent) { file in
                                let fileName = file.lastPathComponent
                                Button(action: {
                                    selectedFile = fileName
                                }) {
                                    HStack {
                                        Text(fileName)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        
                                        // Status indicator
                                        let state = transcriptionState.getState(for: fileName)
                                        if state.isProcessing {
                                            Text("\(Int(state.progress * 100))%")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .frame(width: 35, alignment: .trailing)
                                        } else if state.error != nil {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(.red)
                                        } else if !state.result.isEmpty {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                        }
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 6)
                                    .background(selectedFile == fileName ? Color.blue.opacity(0.1) : Color.clear)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                            }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                        handleFileDrop(providers: providers)
                    }
                    
                    // Untranscribed Section
                    VStack(spacing: 0) {
                        Text("Untranscribed")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.1))
                        
                        let inProgressCount = directoryMonitor.files.filter { file in
                            let state = transcriptionState.getState(for: file.lastPathComponent)
                            return state.isProcessing
                        }.count

                        let untranscribedCount = directoryMonitor.files.filter { file in
                            let state = transcriptionState.getState(for: file.lastPathComponent)
                            return state.result.isEmpty && !state.isProcessing
                        }.count

                        if inProgressCount > 0 {
                            Text("\(untranscribedCount) files untranscribed (\(inProgressCount) in progress)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(untranscribedCount) files untranscribed")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(height: 80)
                }
                .frame(minWidth: 200, maxWidth: 300)
                .background(Color(NSColor.windowBackgroundColor))
                
                // Right content area (Transcription View)
                TranscriptionView(
                    selectedFile: selectedFile,
                    transcriptionState: transcriptionState,
                    selectedDirectory: selectedDirectory
                )
            }
        }
        .frame(minWidth: 800, minHeight: 500)
    }
    
    private struct TranscriptionView: View {
        let selectedFile: String?
        @ObservedObject var transcriptionState: TranscriptionManager.TranscriptionState
        let selectedDirectory: URL?
        
        var body: some View {
            VStack {
                Text("Transcription")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.1))
                
                if let selectedFile = selectedFile {
                    let state = transcriptionState.getState(for: selectedFile)
                    
                    if state.isProcessing {
                        VStack {
                            ProgressView(value: state.progress)
                                .frame(width: 200)
                            Text("Transcribing... \(Int(state.progress * 100))%")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = state.error {
                        VStack {
                            Text("Error: \(error)")
                                .foregroundColor(.red)
                            Button("Retry Transcription") {
                                if let directory = selectedDirectory {
                                    let fileURL = directory.appendingPathComponent(selectedFile)
                                    TranscriptionManager.shared.addFileToQueue(file: fileURL)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .padding()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !state.result.isEmpty {
                        ScrollView {
                            Text(state.result)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                    } else {
                        VStack {
                            Text("Waiting to start transcription...")
                                .foregroundColor(.secondary)
                            Button("Start Transcription") {
                                if let directory = selectedDirectory {
                                    let fileURL = directory.appendingPathComponent(selectedFile)
                                    TranscriptionManager.shared.addFileToQueue(file: fileURL)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .padding()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    Text("Select a file to view transcription")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
    
    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        guard let selectedDirectory = selectedDirectory else { return false }
        
        Task {
            for provider in providers {
                if let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier),
                   let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    
                    let destinationURL = selectedDirectory.appendingPathComponent(url.lastPathComponent)
                    
                    do {
                        try FileManager.default.copyItem(at: url, to: destinationURL)
                        directoryMonitor.updateDirectory(selectedDirectory)
                        TranscriptionManager.shared.addFileToQueue(file: destinationURL)
                    } catch {
                        print("Error copying file: \(error)")
                    }
                }
            }
        }
        return true
    }
    
    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        
        if panel.runModal() == .OK, let directory = panel.url {
            selectedDirectory = directory
            directoryPath = directory.path
            directoryMonitor.updateDirectory(directory)
            transcriptionManager.setRootDirectory(selectedDirectory: directory) // Correct method name
        }
    }

    private static func transcribeNewFile(_ fileURL: URL) {
        TranscriptionManager.shared.addFileToQueue(file: fileURL)
    }
}

#Preview {
    ContentView()
}

import Foundation

class TranscriptionManager {
    static let shared = TranscriptionManager()

    // MARK: - TranscriptionState
    class TranscriptionState: ObservableObject {
        @Published var states: [String: FileState] = [:]

        struct FileState: Equatable {
            var isProcessing: Bool = false
            var result: String = ""
            var error: String? = nil
            var progress: Double = 0.0
        }

        func updateProgress(for fileName: String, progress: Double) {
            DispatchQueue.main.async {
                var state = self.states[fileName] ?? FileState()
                state.progress = progress
                self.states[fileName] = state
            }
        }

        func updateState(for fileName: String, isProcessing: Bool, result: String? = nil, error: String? = nil) {
            DispatchQueue.main.async {
                var state = self.states[fileName] ?? FileState()
                state.isProcessing = isProcessing
                if let result = result { state.result = result }
                state.error = error
                if !isProcessing { state.progress = 0.0 }
                self.states[fileName] = state
            }
        }

        func getState(for fileName: String) -> FileState {
            return states[fileName] ?? FileState()
        }
    }

    // MARK: - Properties
    let state = TranscriptionState()
    private var rootDirectory: URL?
    private var fileQueue: [URL] = []
    private var isProcessing: Bool = false

    private init() {}

    // MARK: - Directory Management
    func setRootDirectory(selectedDirectory: URL) {
        rootDirectory = selectedDirectory
        createCentralResultsFolder()
    }

    private func createCentralResultsFolder() {
        guard let rootDirectory = rootDirectory else { return }
        let resultsFolder = rootDirectory.appendingPathComponent("TranscriptionResults")
        if !FileManager.default.fileExists(atPath: resultsFolder.path) {
            do {
                try FileManager.default.createDirectory(at: resultsFolder, withIntermediateDirectories: true)
                print("Created centralized results folder: \(resultsFolder.path)")
            } catch {
                print("Failed to create centralized results folder: \(error.localizedDescription)")
            }
        }
    }

    private func getCentralResultsFolder() -> URL? {
        guard let rootDirectory = rootDirectory else { return nil }
        return rootDirectory.appendingPathComponent("TranscriptionResults")
    }

    // MARK: - Progress Management
    func saveProgress(fileURL: URL, lastProcessedFrame: Int) {
        guard let resultsFolder = getCentralResultsFolder() else { return }
        let progressFile = resultsFolder.appendingPathComponent("progress.json")
        updateProgressFile(progressFile, fileName: fileURL.lastPathComponent, frame: lastProcessedFrame)
    }

    private func updateProgressFile(_ progressFile: URL, fileName: String, frame: Int) {
        var progressData: [String: Int] = [:]
        if let data = try? Data(contentsOf: progressFile),
           let loadedProgress = try? JSONDecoder().decode([String: Int].self, from: data) {
            progressData = loadedProgress
        }
        progressData[fileName] = frame
        if let data = try? JSONEncoder().encode(progressData) {
            try? data.write(to: progressFile)
        }
    }

    func loadProgress(fileURL: URL) -> Int {
        guard let resultsFolder = getCentralResultsFolder() else { return 0 }
        let progressFile = resultsFolder.appendingPathComponent("progress.json")
        return readProgressFromFile(progressFile, fileName: fileURL.lastPathComponent)
    }

    private func readProgressFromFile(_ progressFile: URL, fileName: String) -> Int {
        guard let data = try? Data(contentsOf: progressFile),
              let progress = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return 0
        }
        return progress[fileName] ?? 0
    }

    // MARK: - Result Management
    func getResult(for file: URL) -> String? {
        guard let resultsFolder = getCentralResultsFolder() else { return nil }
        let resultFile = resultsFolder.appendingPathComponent("\(file.lastPathComponent).txt")
        return try? String(contentsOf: resultFile)
    }

    func appendResult(for file: URL, resultChunk: String) {
        guard let resultsFolder = getCentralResultsFolder() else { return }
        let centralizedResultFile = resultsFolder.appendingPathComponent("\(file.lastPathComponent).txt")

        if let fileHandle = try? FileHandle(forWritingTo: centralizedResultFile) {
            fileHandle.seekToEndOfFile()
            if let data = resultChunk.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        } else {
            try? resultChunk.write(to: centralizedResultFile, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Queue Management
    func addFileToQueue(file: URL) {
        let fileName = file.lastPathComponent
        if let result = getResult(for: file) {
            state.updateState(for: fileName, isProcessing: false, result: result)
            return
        }
        if !fileQueue.contains(file) {
            fileQueue.append(file)
            state.updateState(for: fileName, isProcessing: true)
            processNextFile()
        }
    }

    private func processNextFile() {
        guard !isProcessing, !fileQueue.isEmpty else { return }

        isProcessing = true
        let file = fileQueue.removeFirst()
        let fileName = file.lastPathComponent

        Task {
            do {
                let startFrame = loadProgress(fileURL: file)
                let transcription = try await Transcriber.transcribeVideo(
                    fileURL: file,
                    startFrame: startFrame
                ) { [weak self] current, total, transcriptionChunk in
                    let progress = Double(current) / Double(total)
                    self?.state.updateProgress(for: fileName, progress: progress)
                    self?.appendResult(for: file, resultChunk: transcriptionChunk)
                    self?.saveProgress(fileURL: file, lastProcessedFrame: current)
                }
                
                // Save the final transcription result
                appendResult(for: file, resultChunk: transcription)
                state.updateState(for: fileName, isProcessing: false, result: transcription)
                print("Transcription completed for \(fileName)")
            } catch {
                state.updateState(for: fileName, isProcessing: false, error: error.localizedDescription)
                print("Failed to transcribe \(fileName): \(error.localizedDescription)")
            }
            isProcessing = false
            processNextFile()
        }
    }


    func clearQueue() {
        fileQueue.removeAll()
        isProcessing = false
    }
}

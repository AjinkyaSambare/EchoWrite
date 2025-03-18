import Foundation
import SwiftWhisper

class WhisperModel {
    static let shared = WhisperModel() // Singleton for shared access
    
    private var whisper: Whisper? // SwiftWhisper model instance
    private let params: WhisperParams
    private let chunkSize: Int = 16000 * 60 // 60 seconds at 16kHz
    private var isModelLoaded = false
    
    private init() {
        // Configure WhisperParams for English
        params = WhisperParams()
        params.language = .english
        params.translate = false
        params.print_progress = true
        params.print_timestamps = false
        
        // Load model immediately on initialization
        loadBinaryModel()
    }
    
    private func loadBinaryModel() {
        guard !isModelLoaded else { return }
        
        do {
            if let modelPath = Bundle.main.path(forResource: "ggml-tiny.en", ofType: "bin") {
                let modelURL = URL(fileURLWithPath: modelPath)
                whisper = try Whisper(fromFileURL: modelURL)
                whisper?.params = params
                isModelLoaded = true
                print("Tiny binary model loaded successfully from \(modelURL.path)")
            } else {
                print("Error: Tiny binary model file not found in the app bundle.")
            }
        } catch {
            print("Error loading Whisper model: \(error.localizedDescription)")
        }
    }
    
    /// Forces a reload of the model if needed
    func reloadModelIfNeeded() {
        if !isModelLoaded {
            loadBinaryModel()
        }
    }
    
    /// Transcribes audio frames using sequential chunk processing and live updates.
    /// - Parameters:
    ///   - audioFrames: The full array of audio frames.
    ///   - progressCallback: A callback function to receive progress updates.
    /// - Returns: The final transcription result as a String.
    func transcribeAudio(audioFrames: [Float], progressCallback: @escaping (Int, Int, String) -> Void) async throws -> String {
        // Ensure model is loaded
        if !isModelLoaded {
            loadBinaryModel()
        }
        
        guard let whisper = whisper else {
            throw NSError(
                domain: "WhisperModel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Whisper model not loaded. Please check model file existence and permissions."]
            )
        }

        print("Starting transcription using sequential processing. Total audio frames: \(audioFrames.count)")
        
        // Calculate chunks
        let chunks = stride(from: 0, to: audioFrames.count, by: chunkSize).map {
            Array(audioFrames[$0 ..< min($0 + chunkSize, audioFrames.count)])
        }
        
        var transcriptions = [String]()
        
        for (index, chunk) in chunks.enumerated() {
            print("Processing chunk \(index + 1) / \(chunks.count)...")
            
            do {
                let segments = try await whisper.transcribe(audioFrames: chunk)
                let chunkResult = segments.map { $0.text }.joined(separator: " ")
                transcriptions.append(chunkResult)
                
                // Call the progress callback with current progress
                progressCallback(index + 1, chunks.count, chunkResult)
            } catch {
                print("Error processing chunk \(index + 1): \(error.localizedDescription)")
                throw error
            }
        }
        
        let finalTranscription = transcriptions.joined(separator: " ")
        print("Sequential transcription completed successfully.")
        return finalTranscription
    }
    
    /// Checks if the model is currently loaded and ready
    var isReady: Bool {
        isModelLoaded && whisper != nil
    }
    
    /// Returns the current model status as a string
    var modelStatus: String {
        if isModelLoaded {
            return "Model loaded and ready"
        } else {
            return "Model not loaded"
        }
    }
}

import Foundation
import AVFoundation
import SwiftWhisper

class Transcriber {
    
    /// Extracts audio from a video file and converts it to 16kHz PCM audio frames.
    /// - Parameter fileURL: The URL of the input video file.
    /// - Returns: An array of `Float` values representing the 16kHz PCM audio frames.
    static func convertVideoToPCM(fileURL: URL) async throws -> [Float] {
        print("Extracting audio from video file at URL: \(fileURL)")
        let asset = AVAsset(url: fileURL)
        let reader = try AVAssetReader(asset: asset)

        // Load audio tracks asynchronously
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw NSError(domain: "Transcriber", code: 2, userInfo: [NSLocalizedDescriptionKey: "No audio tracks found in the video file."])
        }
        // Configure audio track output settings
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000, // Target 16kHz sample rate
            AVNumberOfChannelsKey: 1, // Mono audio
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()

        var audioFrames = [Float]()
        while reader.status == .reading {
            if let sampleBuffer = output.copyNextSampleBuffer(),
               let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                let length = CMBlockBufferGetDataLength(blockBuffer)
                var data = Data(count: length)
                data.withUnsafeMutableBytes { bytes in
                    if let baseAddress = bytes.baseAddress {
                        CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: baseAddress)
                    }
                }

                // Convert PCM data to Float
                let pcmBuffer = data.withUnsafeBytes {
                    Array(UnsafeBufferPointer<Int16>(start: $0.bindMemory(to: Int16.self).baseAddress, count: length / MemoryLayout<Int16>.size))
                }
                audioFrames.append(contentsOf: pcmBuffer.map { Float($0) / Float(Int16.max) })
            }
        }

        if reader.status == .completed {
            print("Audio successfully extracted and converted to PCM. Total frames: \(audioFrames.count)")
            return audioFrames
        } else {
            let errorDescription = reader.error?.localizedDescription ?? "Unknown error"
            throw NSError(domain: "Transcriber", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to read audio data. \(errorDescription)"])
        }
    }
    
    /// Transcribes the audio from a video file using parallel chunk processing.
    /// - Parameters:
    ///   - fileURL: The URL of the video file to transcribe.
    ///   - progressCallback: Progress update closure.
    ///   - startFrame: The frame index to resume transcription from.
    static func transcribeVideo(fileURL: URL, startFrame: Int = 0, progressCallback: @escaping (Int, Int, String) -> Void) async throws -> String {
           print("Transcribing video file: \(fileURL)")
           
           let audioFrames = try await convertVideoToPCM(fileURL: fileURL)
           print("Audio frames extracted from video: \(audioFrames.count)")
           
           let whisper = WhisperModel.shared
           var transcriptionResult = ""
           let chunkSize = 960000 // Process 3 seconds of audio at a time (16kHz * 3)
           
           for frameIndex in stride(from: startFrame, to: audioFrames.count, by: chunkSize) {
               let endFrame = min(frameIndex + chunkSize, audioFrames.count)
               let chunk = Array(audioFrames[frameIndex..<endFrame])
               
               let currentChunk = frameIndex / chunkSize + 1
               let totalChunks = (audioFrames.count + chunkSize - 1) / chunkSize
               
               let chunkResult = try await whisper.transcribeAudio(
                   audioFrames: chunk,
                   progressCallback: { (current: Int, total: Int, message: String) in
                       progressCallback(current, total, message)
                   }
               )
               transcriptionResult += chunkResult
               
               // Report progress after each chunk
               progressCallback(currentChunk, totalChunks, chunkResult)
               
               // Save progress
               TranscriptionManager.shared.saveProgress(fileURL: fileURL, lastProcessedFrame: frameIndex)
           }
           
           print("Transcription completed successfully.")
           return transcriptionResult
       }
   }

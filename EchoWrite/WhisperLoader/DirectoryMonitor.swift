import Foundation

class DirectoryMonitor: ObservableObject {
    @Published var files: [URL] = []
    
    private var monitoredDirectory: URL?
    private var directoryFileDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?
    private let fileManager = FileManager.default
    private var onFileAdded: ((URL) -> Void)? // Callback for new files

    // Allowed extensions for audio and video files
    private let allowedExtensions: Set<String> = ["mp4", "mp3", "wav", "mkv", "avi", "mov"]

    /// Initialize the monitor
    init(onFileAdded: ((URL) -> Void)? = nil) {
        self.onFileAdded = onFileAdded
    }

    /// Update the monitored directory
    func updateDirectory(_ newDirectory: URL) {
        stopMonitoring()
        self.monitoredDirectory = newDirectory
        files.removeAll()
        startMonitoring(directory: newDirectory)
    }

    /// Start monitoring the directory
    private func startMonitoring(directory: URL) {
        scanExistingFiles(directory: directory)

        directoryFileDescriptor = open(directory.path, O_EVTONLY)
        guard directoryFileDescriptor != -1 else {
            print("Failed to open directory: \(directory.path)")
            return
        }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.global()
        )

        source?.setEventHandler { [weak self] in
            self?.scanExistingFiles(directory: directory)
        }

        source?.setCancelHandler {
            close(self.directoryFileDescriptor)
        }

        source?.resume()
        print("Started monitoring: \(directory.path)")
    }

    /// Stop monitoring
    func stopMonitoring() {
        source?.cancel()
        source = nil
        if directoryFileDescriptor != -1 {
            close(directoryFileDescriptor)
            directoryFileDescriptor = -1
        }
    }

    /// Recursively scan directory for files and notify on new additions
    private func scanExistingFiles(directory: URL) {
        do {
            let allFiles = try fetchAllFilesRecursively(directory: directory)
                .filter { allowedExtensions.contains($0.pathExtension.lowercased()) } // Filter allowed file types
            
            // Check for new files
            let newFileURLs = allFiles.filter { !files.contains($0) }
            DispatchQueue.main.async {
                self.files = allFiles
                for newFile in newFileURLs {
                    print("New file detected: \(newFile.lastPathComponent)")
                    self.onFileAdded?(newFile) // Notify about the new file
                }
            }
        } catch {
            print("Error scanning directory: \(error.localizedDescription)")
        }
    }
    
    /// Helper method to fetch all files recursively
    private func fetchAllFilesRecursively(directory: URL) throws -> [URL] {
        var allFiles: [URL] = []
        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        
        for item in contents {
            if item.hasDirectoryPath {
                let subdirectoryFiles = try fetchAllFilesRecursively(directory: item)
                allFiles.append(contentsOf: subdirectoryFiles)
            } else {
                allFiles.append(item)
            }
        }
        
        return allFiles
    }
}

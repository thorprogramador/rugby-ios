import Foundation

// MARK: - S3 Configuration

public struct S3Configuration {
    public let endpoint: String
    public let bucket: String
    public let accessKey: String
    public let secretKey: String
    
    public init(endpoint: String, bucket: String, accessKey: String, secretKey: String) {
        self.endpoint = endpoint
        self.bucket = bucket
        self.accessKey = accessKey
        self.secretKey = secretKey
    }
}

// MARK: - Interface

/// The protocol describing a manager to upload cached binaries to remote storage.
public protocol IUploadManager: AnyObject {
    /// Refreshes the +latest file with current cached binaries.
    func refreshLatestFile() async throws
    
    /// Uploads binaries to S3 storage.
    /// - Parameters:
    ///   - s3Config: S3 configuration settings.
    ///   - dryRun: Whether to perform a dry run without actual uploading.
    ///   - processes: Number of parallel upload processes.
    ///   - archiveType: Archive type to use (zip or 7z).
    func upload(s3Config: S3Configuration,
                dryRun: Bool,
                processes: Int,
                archiveType: ArchiveType) async throws
}

// MARK: - Implementation

final class UploadManager: Loggable {
    let logger: ILogger
    
    init(logger: ILogger) {
        self.logger = logger
    }
    
    private func getRugbyUploaderScriptPath() throws -> String {
        // Try to get the bundled resource first
        if let resourceURL = Bundle.main.url(forResource: "rugby-s3-uploader", withExtension: "rb") {
            return resourceURL.path
        }
        
        // Try alternative bundle access for SPM resources
        let bundle = Bundle(for: type(of: self))
        if let resourceURL = bundle.url(forResource: "rugby-s3-uploader", withExtension: "rb") {
            return resourceURL.path
        }
        
        // Fallback: try to find the ruby script in the project directory (for development)
        let projectPaths = [
            // Development path - in the source tree
            URL(fileURLWithPath: #file)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("rugby-s3-uploader.rb").path,
            
            // Installed path - next to rugby executable  
            URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
                .deletingLastPathComponent()
                .appendingPathComponent("rugby-s3-uploader.rb").path
        ]
        
        // Try to find existing script
        for path in projectPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        throw UploadManagerError.rubyScriptNotFound("Could not find rugby-s3-uploader.rb in bundle or project")
    }
    
    private func runRugbyUploader(arguments: [String], environment: [String: String] = [:]) async throws {
        let scriptPath = try getRugbyUploaderScriptPath()
        
        // Check if ruby script exists
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw UploadManagerError.rubyScriptNotFound(scriptPath)
        }
        
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            env[key] = value
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ruby", scriptPath] + arguments
        process.environment = env
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw UploadManagerError.rubyScriptFailed("Process failed with exit code \(process.terminationStatus)")
        }
    }
}

// MARK: - IUploadManager

extension UploadManager: IUploadManager {
    func refreshLatestFile() async throws {
        await log("🏈 Rugby: Refreshing +latest file with cached binaries...")
        try await runRugbyUploader(arguments: ["--refresh"])
    }
    
    func upload(s3Config: S3Configuration,
                dryRun: Bool,
                processes: Int,
                archiveType: ArchiveType) async throws {
        var arguments = ["--upload"]
        let environment: [String: String] = [
            "S3_ENDPOINT": s3Config.endpoint,
            "S3_BUCKET": s3Config.bucket,
            "S3_ACCESS_KEY": s3Config.accessKey,
            "S3_SECRET_KEY": s3Config.secretKey
        ]
        
        if dryRun {
            arguments.append("--dry-run")
        }
        
        arguments.append("--processes")
        arguments.append("\(processes)")
        
        if archiveType == .sevenZip {
            arguments.append("--7zip")
        }
        
        try await runRugbyUploader(arguments: arguments, environment: environment)
    }
}

// MARK: - Errors

enum UploadManagerError: LocalizedError {
    case rubyScriptNotFound(String)
    case rubyScriptFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .rubyScriptNotFound(let path):
            return "Rugby S3 uploader script not found at: \(path)"
        case .rubyScriptFailed(let output):
            return "Rugby S3 uploader failed: \(output)"
        }
    }
}

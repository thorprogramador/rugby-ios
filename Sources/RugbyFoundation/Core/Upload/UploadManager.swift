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
    private let s3Uploader: RugbyS3Uploader
    
    init(logger: ILogger) {
        self.logger = logger
        self.s3Uploader = RugbyS3Uploader(logger: logger)
    }
}

// MARK: - IUploadManager

extension UploadManager: IUploadManager {
    func refreshLatestFile() async throws {
        try await s3Uploader.refreshLatestFile(dryRun: false)
    }
    
    func upload(s3Config: S3Configuration,
                dryRun: Bool,
                processes: Int,
                archiveType: ArchiveType) async throws {
        try await s3Uploader.uploadToS3(
            s3Config: s3Config,
            dryRun: dryRun,
            refreshFirst: false, // Already handled by the Upload command
            processes: processes,
            archiveType: archiveType
        )
    }
}

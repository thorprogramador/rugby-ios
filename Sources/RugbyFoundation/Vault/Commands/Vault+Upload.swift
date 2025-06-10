import Foundation

extension Vault {
    /// The manager to upload binaries to remote storage.
    public func uploadManager() -> IUploadManager {
        UploadManager(logger: logger)
    }
}

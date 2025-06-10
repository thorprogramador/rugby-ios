import ArgumentParser
import Fish
import Foundation
import RugbyFoundation

struct Upload: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "upload",
        abstract: "Upload binaries to remote storage.",
        discussion: """
        \(Links.commandsHelp("upload.md"))
        \(Links.docs("remote-cache.md"))
        """
    )

    @Option(help: "S3 endpoint URL (e.g., s3.eu-west-2.amazonaws.com).")
    var endpoint: String?

    @Option(help: "S3 bucket name.")
    var bucket: String?

    @Option(help: "S3 access key. Can also be set via S3_ACCESS_KEY environment variable.")
    var accessKey: String?

    @Option(help: "S3 secret key. Can also be set via S3_SECRET_KEY environment variable.")
    var secretKey: String?

    @Flag(help: "Refresh +latest file before uploading.")
    var refresh = false

    @Flag(help: "Show what would be uploaded without actually uploading.")
    var dryRun = false

    @Option(help: "Number of parallel upload processes.")
    var processes = 10

    @Option(help: "Binary archive file type to use: zip or 7z.")
    var archiveType: ArchiveType = .zip

    @Option(help: "Timeout for uploads in seconds.")
    var timeout = 300

    @OptionGroup
    var commonOptions: CommonOptions

    func run() async throws {
        try await run(body,
                      outputType: commonOptions.output,
                      logLevel: commonOptions.logLevel)
    }
}

// MARK: - Body

extension Upload: RunnableCommand {
    enum Error: LocalizedError {
        case missingS3Configuration([String])
        case missingBinariesFile
        case noBinariesFound

        var errorDescription: String? {
            switch self {
            case let .missingS3Configuration(keys):
                return """
                Missing S3 configuration. Please provide:
                \(keys.map { "  --\($0.lowercased().replacingOccurrences(of: "_", with: "-"))" }.joined(separator: "\n"))
                
                Or set environment variables:
                \(keys.map { "  \($0)" }.joined(separator: "\n"))
                """
            case .missingBinariesFile:
                return "No +latest file found. Run with --refresh or 'rugby cache' first."
            case .noBinariesFound:
                return "No binaries found in +latest file."
            }
        }
    }

    func body() async throws {
        let uploadManager = dependencies.uploadManager()
        
        let s3Config = try resolveS3Configuration()
        
        if refresh {
            try await uploadManager.refreshLatestFile()
        }
        
        try await uploadManager.upload(
            s3Config: s3Config,
            dryRun: dryRun,
            processes: processes,
            archiveType: archiveType
        )
    }

    private func resolveS3Configuration() throws -> S3Configuration {
        let endpointValue = endpoint ?? Environment.s3Endpoint
        let bucketValue = bucket ?? Environment.s3Bucket
        let accessKeyValue = accessKey ?? Environment.s3AccessKey
        let secretKeyValue = secretKey ?? Environment.s3SecretKey

        var missing: [String] = []
        if endpointValue?.isEmpty != false { missing.append("S3_ENDPOINT") }
        if bucketValue?.isEmpty != false { missing.append("S3_BUCKET") }
        if accessKeyValue?.isEmpty != false { missing.append("S3_ACCESS_KEY") }
        if secretKeyValue?.isEmpty != false { missing.append("S3_SECRET_KEY") }

        guard missing.isEmpty else {
            throw Error.missingS3Configuration(missing)
        }

        return S3Configuration(
            endpoint: endpointValue!,
            bucket: bucketValue!,
            accessKey: accessKeyValue!,
            secretKey: secretKeyValue!
        )
    }
}

// MARK: - Environment Extensions

private extension Environment {
    static var s3Endpoint: String? { ProcessInfo.processInfo.environment["S3_ENDPOINT"] }
    static var s3Bucket: String? { ProcessInfo.processInfo.environment["S3_BUCKET"] }
    static var s3AccessKey: String? { ProcessInfo.processInfo.environment["S3_ACCESS_KEY"] }
    static var s3SecretKey: String? { ProcessInfo.processInfo.environment["S3_SECRET_KEY"] }
}

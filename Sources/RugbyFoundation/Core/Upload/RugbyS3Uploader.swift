import Foundation
import Fish
import CryptoKit

// MARK: - RugbyS3Uploader

public final class RugbyS3Uploader: Loggable {
    public let logger: ILogger
    private let sharedPath: String
    private let binPath: String
    private let latestBinariesPath: String
    private let uploadSession: URLSession
    
    public init(logger: ILogger) {
        self.logger = logger
        let expandedPath = NSString(string: "~/.rugby").expandingTildeInPath
        self.sharedPath = expandedPath
        self.binPath = "\(expandedPath)/bin"
        self.latestBinariesPath = "\(binPath)/+latest"
        
        // Create a reusable session for uploads with optimized configuration
        let configuration = URLSessionConfiguration.default
        configuration.allowsCellularAccess = true
        configuration.httpMaximumConnectionsPerHost = 20 // Allow more parallel connections
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 600
        configuration.httpShouldUsePipelining = true
        self.uploadSession = URLSession(configuration: configuration)
    }
    
    // MARK: - Public Methods
    
    public func refreshLatestFile(dryRun: Bool = false) async throws {
        await log("🏈 Rugby: Refreshing +latest file with all cached binaries...")
        
        guard FileManager.default.fileExists(atPath: binPath) else {
            throw RugbyS3UploaderError.binDirectoryNotFound(binPath)
        }
        
        await log("🔍 Scanning for cached binaries...")
        let allBinaries = try await findAllBinaries()
        
        if allBinaries.isEmpty {
            throw RugbyS3UploaderError.noCachedBinariesFound(binPath)
        }
        
        // Group by target/config and keep only the latest binary for each
        let latestBinaries = try await getLatestBinaries(from: allBinaries)
        let sortedBinaries = latestBinaries.sorted()
        
        await log("📦 Found \(sortedBinaries.count) latest binaries (one per target/config)")
        
        if !dryRun {
            // Backup existing +latest file if it exists
            if FileManager.default.fileExists(atPath: latestBinariesPath) {
                // Always use microsecond precision to avoid timestamp conflicts
                let microTimestamp = String(format: "%.6f", Date().timeIntervalSince1970).replacingOccurrences(of: ".", with: "")
                let backupFile = "\(latestBinariesPath).backup.\(microTimestamp)"
                
                // Force remove any existing backup file with same name
                try? FileManager.default.removeItem(atPath: backupFile)
                
                do {
                    try FileManager.default.copyItem(atPath: latestBinariesPath, toPath: backupFile)
                    await log("💾 Backed up existing +latest file to: \(URL(fileURLWithPath: backupFile).lastPathComponent)")
                } catch {
                    // Fallback: try with additional random suffix
                    let randomSuffix = String(Int.random(in: 1000...9999))
                    let fallbackBackupFile = "\(latestBinariesPath).backup.\(microTimestamp).\(randomSuffix)"
                    try? FileManager.default.removeItem(atPath: fallbackBackupFile)
                    
                    do {
                        try FileManager.default.copyItem(atPath: latestBinariesPath, toPath: fallbackBackupFile)
                        await log("💾 Backed up existing +latest file to: \(URL(fileURLWithPath: fallbackBackupFile).lastPathComponent)")
                    } catch {
                        await log("⚠️ Warning: Could not create backup file, continuing without backup: \(error.localizedDescription)")
                    }
                }
            }
            
            // Remove existing +latest file before writing new content
            if FileManager.default.fileExists(atPath: latestBinariesPath) {
                try? FileManager.default.removeItem(atPath: latestBinariesPath)
                await log("🗑️ Removed existing +latest file")
            }
            
            // Write all binary paths to +latest file
            let content = sortedBinaries.joined(separator: "\n") + "\n"
            try content.write(toFile: latestBinariesPath, atomically: true, encoding: .utf8)
            await log("✅ Successfully refreshed +latest file with \(sortedBinaries.count) latest binaries (one per target/config)")
        } else {
            await log("🧪 DRY RUN: Would write \(sortedBinaries.count) binaries to +latest file")
        }
        
        await log("📄 File location: \(latestBinariesPath)")
        
        // Show sample of what was written
        await log("")
        await log("📋 Sample of binaries:")
        let sampleCount = min(5, sortedBinaries.count)
        for i in 0..<sampleCount {
            await log("   \(sortedBinaries[i])")
        }
        if sortedBinaries.count > 5 {
            await log("   ... and \(sortedBinaries.count - 5) more")
        }
        
        await log("")
        await log("🚀 Your +latest file is now ready for S3 upload scripts!")
    }
    
    public func showCurrentBinaries(dryRun: Bool = false) async throws {
        await log("🏈 Rugby: Current cached binaries")
        
        if FileManager.default.fileExists(atPath: latestBinariesPath) {
            let content = try String(contentsOfFile: latestBinariesPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty {
                await log("📄 +latest file exists but is empty")
            } else {
                let binaries = content.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
                await log("📄 +latest file contains \(binaries.count) binaries:")
                for binary in binaries {
                    await log("   \(binary)")
                }
            }
        } else {
            await log("❌ No +latest file found at \(latestBinariesPath)")
        }
        
        // Also show what exists in the filesystem
        await log("")
        if dryRun {
            try await refreshLatestFile(dryRun: true)
        }
    }
    
    public func uploadToS3(
        s3Config: S3Configuration,
        dryRun: Bool = false,
        refreshFirst: Bool = true,
        processes: Int = 15,
        archiveType: ArchiveType = .zip
    ) async throws {
        await log("🔄 Starting S3 upload process...")
        
        if refreshFirst {
            try await refreshLatestFile(dryRun: false)
        }
        
        guard FileManager.default.fileExists(atPath: latestBinariesPath) else {
            throw RugbyS3UploaderError.missingLatestFile
        }
        
        // Parse binaries from +latest file
        let content = try String(contentsOfFile: latestBinariesPath, encoding: .utf8)
        let binaries = content.split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
            .reduce(into: [String: String]()) { result, path in
                let remotePath = path.replacingOccurrences(of: "\(binPath)/", with: "")
                result[remotePath] = path
            }
        
        if binaries.isEmpty {
            throw RugbyS3UploaderError.noBinariesInLatestFile
        }
        
        await log("📦 Found \(binaries.count) binaries to upload")
        
        if dryRun {
            await log("🧪 DRY RUN: Would upload these binaries:")
            for (remotePath, localPath) in binaries {
                await log("   \(remotePath) <- \(localPath)")
            }
            return
        }
        
        await log("🚀 Starting upload to S3...")
        await log("📦 Uploading \(binaries.count) binaries using \(processes) parallel processes")
        await log("🗜️  Compression: \(archiveType == .sevenZip ? "7zip" : "zip")")
        
        // Determine if endpoint already includes bucket
        var cleanEndpoint = s3Config.endpoint
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        
        // Check if endpoint contains bucket in path format (e.g., s3.region.amazonaws.com/bucket)
        let pathComponents = cleanEndpoint.split(separator: "/")
        let endpointContainsBucketInPath = pathComponents.count > 1 && String(pathComponents.last!) == s3Config.bucket
        
        // Extract actual endpoint if bucket is in path
        if endpointContainsBucketInPath {
            cleanEndpoint = String(pathComponents.dropLast().joined(separator: "/"))
        }

        // Extract region from endpoint
        let region = extractRegionFromEndpoint(s3Config.endpoint)
        
        // Create modified config with cleaned endpoint
        let cleanedConfig = S3Configuration(
            endpoint: cleanEndpoint,
            bucket: s3Config.bucket,
            accessKey: s3Config.accessKey,
            secretKey: s3Config.secretKey
        )
        
        // Test S3 connection with HEAD request
        let testSuccessful = await testS3Connection(
            config: cleanedConfig, 
            region: region,
            endpointContainsBucket: false  // Already cleaned
        )
        if testSuccessful {
            await log("✅ S3 connection successful")
        } else {
            throw RugbyS3UploaderError.s3ConnectionFailed("Failed to connect to S3 bucket")
        }
        
        // Upload binaries in parallel
        let results = await uploadBinariesInParallel(
            binaries: binaries,
            s3Config: cleanedConfig,
            region: region,
            archiveType: archiveType,
            maxConcurrency: processes,
            endpointContainsBucket: false  // Already cleaned
        )
        
        // Count results
        let uploadedCount = results.filter { $0.success }.count
        let failedCount = results.filter { !$0.success }.count
        
        await log("")
        await log("📊 Upload Summary:")
        await log("   ✅ Successfully uploaded: \(uploadedCount)")
        if failedCount > 0 {
            await log("   ❌ Failed: \(failedCount)")
        }
        await log("   📦 Total processed: \(binaries.count)")
    }
    
    // MARK: - Private Methods
    
    private func findAllBinaries() async throws -> [String] {
        var allBinaries: [String] = []
        let fileManager = FileManager.default
        
        func scanDirectory(at path: String, depth: Int = 0) throws {
            guard let enumerator = fileManager.enumerator(atPath: path) else { return }
            
            for case let file as String in enumerator {
                let fullPath = "\(path)/\(file)"
                var isDirectory: ObjCBool = false
                
                if fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory) && isDirectory.boolValue {
                    // Check if this is a binary hash directory (should be 3 levels deep from bin/)
                    let relativePath = fullPath.replacingOccurrences(of: "\(binPath)/", with: "")
                    let components = relativePath.split(separator: "/")
                    
                    if components.count == 3,
                       let lastComponent = components.last,
                       lastComponent.range(of: "^[a-f0-9]+$", options: .regularExpression) != nil {
                        allBinaries.append(fullPath)
                        enumerator.skipDescendants()
                    }
                }
            }
        }
        
        try scanDirectory(at: binPath)
        return allBinaries
    }
    
    private func getLatestBinaries(from allBinaries: [String]) async throws -> [String] {
        var latestBinaries: [String: (path: String, mtime: Date)] = [:]
        let fileManager = FileManager.default
        
        for binaryPath in allBinaries {
            let targetConfig = URL(fileURLWithPath: binaryPath).deletingLastPathComponent().path
            
            if let attributes = try? fileManager.attributesOfItem(atPath: binaryPath),
               let mtime = attributes[.modificationDate] as? Date {
                
                if let existing = latestBinaries[targetConfig] {
                    if mtime > existing.mtime {
                        latestBinaries[targetConfig] = (path: binaryPath, mtime: mtime)
                    }
                } else {
                    latestBinaries[targetConfig] = (path: binaryPath, mtime: mtime)
                }
            }
        }
        
        return latestBinaries.values.map(\.path)
    }
    
    private func extractRegionFromEndpoint(_ endpoint: String) -> String {
        // Clean endpoint first
        var cleanEndpoint = endpoint.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        
        // Remove bucket from path if present (e.g., s3.region.amazonaws.com/bucket)
        if cleanEndpoint.contains("/") {
            cleanEndpoint = String(cleanEndpoint.split(separator: "/").first ?? "")
        }
        
        // Extract region from endpoint like "s3.eu-west-2.amazonaws.com"
        // First try s3.region.amazonaws.com format
        if cleanEndpoint.contains("s3.") && cleanEndpoint.contains(".amazonaws.com") {
            let components = cleanEndpoint.split(separator: ".")
            if components.count >= 3 {
                // Find the component after "s3"
                for i in 0..<components.count-1 {
                    if components[i] == "s3" && i+1 < components.count {
                        let region = String(components[i+1])
                        // Validate it looks like a region
                        if region.contains("-") {
                            return region
                        }
                    }
                }
            }
        }
        
        // Try region.s3.amazonaws.com format
        if cleanEndpoint.contains(".s3.amazonaws.com") {
            let components = cleanEndpoint.split(separator: ".")
            if components.count >= 3 && components.first?.contains("-") == true {
                return String(components[0])
            }
        }
        
        // Default to us-east-1 if cannot extract
        return "us-east-1"
    }
    
    private func testS3Connection(config: S3Configuration, region: String, endpointContainsBucket: Bool) async -> Bool {
        // Handle endpoint with or without https://
        let endpoint = config.endpoint.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        
        // Build URL based on whether endpoint contains bucket
        let urlString: String
        if endpointContainsBucket {
            // Endpoint already includes bucket (e.g., rappicache.s3.us-east-1.amazonaws.com)
            // For virtual-hosted-style, just test the root
            urlString = "https://\(endpoint)/"
        } else {
            // For path-style URLs when bucket is separate
            // Try virtual-hosted-style first: bucket.s3.region.amazonaws.com
            if endpoint.starts(with: "s3.") && endpoint.contains(".amazonaws.com") {
                // Convert s3.region.amazonaws.com to bucket.s3.region.amazonaws.com
                urlString = "https://\(config.bucket).\(endpoint)/"
            } else {
                // Fallback to path-style: endpoint/bucket
                urlString = "https://\(endpoint)/\(config.bucket)/"
            }
        }
        
        await log("🔍 Testing S3 connection to: \(urlString)")
        await log("📍 Using region: \(region)")
        
        guard let url = URL(string: urlString) else {
            await log("❌ Invalid URL: \(urlString)")
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        
        let dateString = httpDateString()
        request.setValue(dateString, forHTTPHeaderField: "x-amz-date")
        
        // Sign the request
        let path: String
        let host: String
        
        if endpointContainsBucket {
            path = "/"
            host = endpoint
        } else if endpoint.starts(with: "s3.") && endpoint.contains(".amazonaws.com") {
            // Virtual-hosted-style
            path = "/"
            host = "\(config.bucket).\(endpoint)"
        } else {
            // Path-style
            path = "/\(config.bucket)/"
            host = endpoint
        }
        
        await log("🔐 Signing request with path: \(path), host: \(host)")
        
        // Validate signature inputs before proceeding
        let headersForValidation = [
            "host": host,
            "x-amz-date": dateString
        ]
        
        if !validateSignature(method: "HEAD", path: path, headers: headersForValidation, config: config, region: region) {
            await log("❌ Signature validation failed")
            return false
        }
        
        let signedHeaders = signRequest(
            method: "HEAD",
            path: path,
            headers: [
                "host": host,
                "x-amz-date": dateString
            ],
            payload: Data(),
            config: config,
            region: region,
            service: "s3"
        )
        
        // Set host header explicitly
        request.setValue(host, forHTTPHeaderField: "Host")
        
        for (key, value) in signedHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        do {
            let (data, response) = try await uploadSession.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                await log("📡 S3 HEAD response status: \(httpResponse.statusCode)")
                
                // Log response headers for debugging
                if ProcessInfo.processInfo.environment["RUGBY_DEBUG_S3"] != nil {
                    await log("📡 Response headers:")
                    for (key, value) in httpResponse.allHeaderFields {
                        await log("   \(key): \(value)")
                    }
                }
                
                // Check for authentication errors
                if httpResponse.statusCode == 403 {
                    await log("❌ S3 Authentication failed - check your credentials and signature")
                    if let responseString = String(data: data, encoding: .utf8) {
                        await log("❌ S3 Error response: \(responseString)")
                    }
                } else if httpResponse.statusCode == 404 {
                    await log("⚠️  S3 bucket not found or no access - this might be expected for testing")
                }
                
                return (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404
            }
            return false
        } catch {
            await log("❌ S3 connection error: \(error.localizedDescription)")
            return false
        }
    }
    
    private func uploadBinariesInParallel(
        binaries: [String: String],
        s3Config: S3Configuration,
        region: String,
        archiveType: ArchiveType,
        maxConcurrency: Int,
        endpointContainsBucket: Bool
    ) async -> [(remotePath: String, success: Bool)] {
        await binaries.concurrentMap(maxInParallel: maxConcurrency) { remotePath, localPath in
            do {
                let success = await self.uploadSingleBinary(
                    localPath: localPath,
                    remotePath: remotePath,
                    s3Config: s3Config,
                    region: region,
                    archiveType: archiveType,
                    endpointContainsBucket: endpointContainsBucket
                )
                
                if success {
                    await self.log("✅ Uploaded: \(remotePath)")
                } else {
                    await self.log("❌ Failed to compress: \(remotePath)")
                }
                
                return (remotePath, success)
            }
        }
    }
    
    private func uploadSingleBinary(
        localPath: String,
        remotePath: String,
        s3Config: S3Configuration,
        region: String,
        archiveType: ArchiveType,
        endpointContainsBucket: Bool
    ) async -> Bool {
        let binaryFolderPath = URL(fileURLWithPath: localPath).deletingLastPathComponent().path
        let binaryName = URL(fileURLWithPath: localPath).lastPathComponent
        
        let archiveFile: String
        let remoteKey: String
        let contentType: String
        let compressCommand: String
        
        switch archiveType {
        case .sevenZip:
            archiveFile = "\(localPath).7z"
            remoteKey = "\(remotePath).7z"
            contentType = "application/x-7z-compressed"
            // -mx1 = fastest compression (less CPU, larger file)
            // -mx3 = fast compression (balanced)
            // -mx5 = normal compression
            // -mx7 = maximum compression (more CPU, smaller file)
            compressCommand = "cd '\(binaryFolderPath)' && 7z a -mx1 -mmt=on '\(binaryName).7z' '\(binaryName)' > /dev/null 2>&1"
        case .zip:
            archiveFile = "\(localPath).zip"
            remoteKey = "\(remotePath).zip"
            contentType = "application/zip"
            // -1 = fastest compression (less CPU, larger file)
            // -6 = default compression
            // -9 = best compression (more CPU, smaller file)
            compressCommand = "cd '\(binaryFolderPath)' && zip -1 -r '\(binaryName).zip' '\(binaryName)' > /dev/null 2>&1"
        }
        
        // Create archive file
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", compressCommand]
        
        // Redirect output to avoid console spam
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        
        do {
            try task.run()
            task.waitUntilExit()
            
            guard task.terminationStatus == 0 else {
                await log("❌ Compression failed for: \(binaryName)")
                return false
            }
            
            // Check if archive was created successfully
            guard FileManager.default.fileExists(atPath: archiveFile) else {
                await log("❌ Archive file not created for: \(binaryName)")
                return false
            }
            
            // Upload to S3 - using memory-mapped data for large files
            let archiveURL = URL(fileURLWithPath: archiveFile)
            let fileData: Data
            
            let fileSize = try FileManager.default.attributesOfItem(atPath: archiveFile)[.size] as? Int ?? 0
            if fileSize > 50_000_000 { // 50MB threshold
                // For large files, use memory mapping
                fileData = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
            } else {
                fileData = try Data(contentsOf: archiveURL)
            }
            
            let uploadSuccess = await uploadToS3(
                data: fileData,
                key: remoteKey,
                contentType: contentType,
                config: s3Config,
                region: region,
                endpointContainsBucket: endpointContainsBucket
            )
            
            // Clean up archive file
            try? FileManager.default.removeItem(atPath: archiveFile)
            
            return uploadSuccess
        } catch {
            // Clean up archive file on error
            try? FileManager.default.removeItem(atPath: archiveFile)
            await log("❌ Error processing \(binaryName): \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - S3 Upload Implementation
    
    private func uploadToS3(
        data: Data,
        key: String,
        contentType: String,
        config: S3Configuration,
        region: String,
        endpointContainsBucket: Bool
    ) async -> Bool {
        // Handle endpoint with or without https://
        let endpoint = config.endpoint.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        
        // Build URL based on whether endpoint contains bucket
        let urlString: String
        let host: String
        let path: String
        
        if endpointContainsBucket {
            // Endpoint already includes bucket (e.g., rappicache.s3.us-east-1.amazonaws.com)
            urlString = "https://\(endpoint)/\(key)"
            host = endpoint
            path = "/\(key)"
        } else if endpoint.starts(with: "s3.") && endpoint.contains(".amazonaws.com") {
            // Virtual-hosted-style: bucket.s3.region.amazonaws.com
            urlString = "https://\(config.bucket).\(endpoint)/\(key)"
            host = "\(config.bucket).\(endpoint)"
            path = "/\(key)"
        } else {
            // Path-style: endpoint/bucket/key
            urlString = "https://\(endpoint)/\(config.bucket)/\(key)"
            host = endpoint
            path = "/\(config.bucket)/\(key)"
        }
        
        guard let url = URL(string: urlString) else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        
        // Increase timeout for large files
        request.timeoutInterval = 300 // 5 minutes
        
        let dateString = httpDateString()
        request.setValue(dateString, forHTTPHeaderField: "x-amz-date")
        
        // Validate signature inputs before proceeding
        let headersForValidation = [
            "host": host,
            "content-type": contentType,
            "content-length": "\(data.count)",
            "x-amz-date": dateString
        ]
        
        if !validateSignature(method: "PUT", path: path, headers: headersForValidation, config: config, region: region) {
            await log("❌ Upload signature validation failed for key: \(key)")
            return false
        }
        
        // Sign the request
        let signedHeaders = signRequest(
            method: "PUT",
            path: path,
            headers: [
                "host": host,
                "content-type": contentType,
                "content-length": "\(data.count)",
                "x-amz-date": dateString
            ],
            payload: data,
            config: config,
            region: region,
            service: "s3"
        )
        
        // Set host header explicitly
        request.setValue(host, forHTTPHeaderField: "Host")
        
        for (key, value) in signedHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        do {
            let (data, response) = try await uploadSession.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if !(200...299).contains(httpResponse.statusCode) {
                    await log("❌ S3 upload failed with status: \(httpResponse.statusCode) for key: \(key)")
                    
                    // Log detailed error information
                    if let responseString = String(data: data, encoding: .utf8) {
                        await log("❌ S3 Error response: \(responseString)")
                    }
                    
                    // Log response headers for debugging authentication issues
                    if ProcessInfo.processInfo.environment["RUGBY_DEBUG_S3"] != nil {
                        await log("📡 Response headers:")
                        for (headerKey, value) in httpResponse.allHeaderFields {
                            await log("   \(headerKey): \(value)")
                        }
                    }
                    
                    // Check for specific error types
                    if httpResponse.statusCode == 403 {
                        await log("❌ Authentication failed - check your S3 credentials and signature")
                    } else if httpResponse.statusCode == 404 {
                        await log("❌ Bucket not found - check your bucket name and region")
                    } else if httpResponse.statusCode == 400 {
                        await log("❌ Bad request - check your request format")
                    }
                }
                return (200...299).contains(httpResponse.statusCode)
            }
            return false
        } catch {
            await log("❌ S3 upload error: \(error.localizedDescription) for key: \(key)")
            return false
        }
    }
    
    // MARK: - AWS Signature V4
    
    private func urlEncodePath(_ path: String) -> String {
        // AWS signature requires specific URL encoding for paths
        // - Don't encode forward slashes
        // - Encode everything else that needs encoding
        let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~/")
        return path.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? path
    }
    
    private func httpDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter.string(from: Date())
    }
    
    private func signRequest(
        method: String,
        path: String,
        headers: [String: String],
        payload: Data,
        config: S3Configuration,
        region: String,
        service: String
    ) -> [String: String] {
        // Validate inputs
        guard !method.isEmpty, !path.isEmpty, !region.isEmpty, !service.isEmpty else {
            print("❌ Invalid signature parameters: method=\(method), path=\(path), region=\(region), service=\(service)")
            return headers
        }
        
        guard !config.accessKey.isEmpty, !config.secretKey.isEmpty else {
            print("❌ Invalid S3 credentials: accessKey and secretKey cannot be empty")
            return headers
        }
        
        let dateString = headers["x-amz-date"] ?? httpDateString()
        let dateStamp = String(dateString.prefix(8))
        
        // URL encode the path for AWS signature
        let encodedPath = urlEncodePath(path)
        
        // Create canonical request - headers must be lowercase and sorted
        let sortedHeaders = headers.sorted { $0.key.lowercased() < $1.key.lowercased() }
        let canonicalHeaders = sortedHeaders
            .map { "\($0.key.lowercased()):\($0.value.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "\n") + "\n" // Must end with newline
        
        let signedHeaders = sortedHeaders
            .map { $0.key.lowercased() }
            .joined(separator: ";")
        
        let payloadHash = SHA256.hash(data: payload)
            .compactMap { String(format: "%02x", $0) }
            .joined()
        
        let canonicalRequest = [
            method,
            encodedPath,
            "", // query string (empty for our use case)
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")
        
        // Create string to sign
        let canonicalRequestHash = SHA256.hash(data: Data(canonicalRequest.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
        
        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            dateString,
            credentialScope,
            canonicalRequestHash
        ].joined(separator: "\n")
        
        // Calculate signature
        let signingKey = getSignatureKey(
            key: config.secretKey,
            dateStamp: dateStamp,
            regionName: region,
            serviceName: service
        )
        
        let signature = hmacSHA256(key: signingKey, data: Data(stringToSign.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
        
        // Validate the generated signature
        if !validateSignatureFormat(signature) {
            print("❌ Generated invalid signature: \(signature)")
            return headers
        }
        
        // Create authorization header
        let authorization = "AWS4-HMAC-SHA256 Credential=\(config.accessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        
        var resultHeaders = headers
        resultHeaders["Authorization"] = authorization
        resultHeaders["x-amz-content-sha256"] = payloadHash
        
        // Enhanced debug logging for signature validation
        if ProcessInfo.processInfo.environment["RUGBY_DEBUG_S3"] != nil {
            print("🔐 AWS Signature V4 Debug:")
            print("   Method: \(method)")
            print("   Path: \(encodedPath)")
            print("   Region: \(region)")
            print("   Date: \(dateString)")
            print("   Canonical Headers: \(canonicalHeaders.replacingOccurrences(of: "\n", with: "\\n"))")
            print("   Signed Headers: \(signedHeaders)")
            print("   Payload Hash: \(payloadHash)")
            print("   Canonical Request Hash: \(canonicalRequestHash)")
            print("   String to Sign: \(stringToSign.replacingOccurrences(of: "\n", with: "\\n"))")
            print("   Authorization: \(authorization)")
        }
        
        return resultHeaders
    }
    
    private func hmacSHA256(key: Data, data: Data) -> Data {
        let key = SymmetricKey(data: key)
        let signature = HMAC<SHA256>.authenticationCode(for: data, using: key)
        return Data(signature)
    }
    
    private func getSignatureKey(
        key: String,
        dateStamp: String,
        regionName: String,
        serviceName: String
    ) -> Data {
        let kSecret = "AWS4\(key)".data(using: .utf8)!
        let kDate = hmacSHA256(key: kSecret, data: Data(dateStamp.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(regionName.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data(serviceName.utf8))
        let kSigning = hmacSHA256(key: kService, data: Data("aws4_request".utf8))
        return kSigning
    }
    
    // MARK: - Signature Validation
    
    private func validateSignature(
        method: String,
        path: String,
        headers: [String: String],
        config: S3Configuration,
        region: String
    ) -> Bool {
        // Check required headers
        let requiredHeaders = ["host", "x-amz-date"]
        for header in requiredHeaders {
            if headers[header]?.isEmpty != false {
                print("❌ Missing required header: \(header)")
                return false
            }
        }
        
        // Validate date format
        if let dateString = headers["x-amz-date"] {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            formatter.timeZone = TimeZone(abbreviation: "UTC")
            if formatter.date(from: dateString) == nil {
                print("❌ Invalid date format in x-amz-date header: \(dateString)")
                return false
            }
        }
        
        // Validate credentials
        if config.accessKey.isEmpty || config.secretKey.isEmpty {
            print("❌ Empty S3 credentials")
            return false
        }
        
        // Validate path
        if !path.hasPrefix("/") {
            print("❌ Path must start with '/': \(path)")
            return false
        }
        
        return true
    }
    
    private func validateSignatureFormat(_ signature: String) -> Bool {
        // AWS signatures should be exactly 64 characters (256 bits in hex)
        guard signature.count == 64 else {
            print("❌ Invalid signature length: \(signature.count), expected 64")
            return false
        }
        
        // Should only contain lowercase hex characters
        let hexPattern = "^[a-f0-9]+$"
        let regex = try? NSRegularExpression(pattern: hexPattern)
        let range = NSRange(location: 0, length: signature.count)
        let matches = regex?.matches(in: signature, range: range) ?? []
        
        if matches.isEmpty {
            print("❌ Invalid signature format: contains non-hex characters")
            return false
        }
        
        return true
    }
    
    // MARK: - Debug Methods
    
    /// Enable debug mode for S3 signature validation
    /// Set RUGBY_DEBUG_S3 environment variable or call this method
    public func enableDebugMode() {
        setenv("RUGBY_DEBUG_S3", "1", 1)
    }
    
    /// Disable debug mode for S3 signature validation
    public func disableDebugMode() {
        unsetenv("RUGBY_DEBUG_S3")
    }
}

// MARK: - Errors

public enum RugbyS3UploaderError: LocalizedError {
    case binDirectoryNotFound(String)
    case noCachedBinariesFound(String)
    case missingLatestFile
    case noBinariesInLatestFile
    case s3ConnectionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .binDirectoryNotFound(let path):
            return """
            ❌ Error: Rugby bin directory not found at \(path)
               Make sure you have run 'rugby build' or 'rugby cache' at least once.
            """
        case .noCachedBinariesFound(let path):
            return """
            ❌ No cached binaries found in \(path)
               Run 'rugby build' or 'rugby cache' to create some binaries first.
            """
        case .missingLatestFile:
            return "❌ No +latest file found. Run with --refresh first."
        case .noBinariesInLatestFile:
            return "❌ No binaries found in +latest file"
        case .s3ConnectionFailed(let error):
            return "❌ S3 connection failed: \(error)"
        }
    }
}

// MARK: - Collection Extension for Concurrent Operations

private extension Dictionary {
    func concurrentMap<T>(
        maxInParallel: Int = Int.max,
        _ transform: @escaping (Key, Value) async throws -> T
    ) async rethrows -> [T] {
        try await withThrowingTaskGroup(of: (offset: Int, value: T).self) { group in
            var offset = 0
            var iterator = makeIterator()
            
            // Start initial tasks
            while offset < maxInParallel, let (key, value) = iterator.next() {
                group.addTask { [offset] in
                    try await (offset, transform(key, value))
                }
                offset += 1
            }
            
            // Collect results and start new tasks
            var result = [T?](repeating: nil, count: count)
            while let transformed = try await group.next() {
                result[transformed.offset] = transformed.value
                
                if let (key, value) = iterator.next() {
                    group.addTask { [offset] in
                        try await (offset, transform(key, value))
                    }
                    offset += 1
                }
            }
            
            return result.compactMap { $0 }
        }
    }
}
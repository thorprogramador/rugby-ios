import ArgumentParser
import Fish
import Foundation
import RugbyFoundation

// MARK: - Error Types

enum SourceLocalChangesError: LocalizedError {
    case gitOutputError(String)
    case gitCommandFailed(String)
    case regexPatternError(String)
    
    var errorDescription: String? {
        switch self {
        case .gitOutputError(let message):
            return "Git output error: \(message)"
        case .gitCommandFailed(let message):
            return "Git command failed: \(message)"
        case .regexPatternError(let message):
            return "Regex pattern error: \(message)"
        }
    }
}

// MARK: - Data Types

struct PodModificationDetails {
    let modificationReason: String
    let modifiedFiles: [String]
}

// MARK: - Command Implementation

struct SourceLocalChanges: RunnableCommand {
    static var configuration = CommandConfiguration(
        commandName: "sourceLocalChanges",
        abstract: "Switch locally modified pods back to source code instead of using cached binaries.",
        discussion: """
        This command detects locally modified podspec files using git and switches the corresponding targets 
        back to source code by performing a rollback operation for those specific targets. This is useful 
        when you've made changes to pod source code and want to quickly switch those pods back to source 
        mode for development while keeping other pods cached.
        
        Use --except to specify pods that should remain in source mode (in addition to the locally modified ones).
        This allows you to preserve any previous exclusions you had when using 'rugby use --except'.
        """
    )

    @OptionGroup
    var commonOptions: CommonOptions

    @Option(
        name: [.short, .long],
        parsing: .upToNextOption,
        help: ArgumentHelp(
            "Regex patterns to exclude targets from using binaries (in addition to locally modified pods). Can be specified multiple times.",
            discussion: """
            Use this option to specify additional pods that should remain in source mode, 
            preserving any previous exclusions you had. You can specify multiple patterns:
            --except NavigationMocks --except PayMocks --except RappiPaymentMethods
            Or use a single regex pattern: --except "NavigationMocks|PayMocks|RappiPaymentMethods"
            """,
            valueName: "regex"
        )
    )
    var except: [String] = []

    func run() async throws {
        try await run(body,
                      outputType: commonOptions.output,
                      logLevel: commonOptions.logLevel)
    }

    func body() async throws {
        let vault = dependencies
        
        // Find all modified files and detect which pods have changes
        let modifiedPods = try await findModifiedPods()
        
        if modifiedPods.isEmpty {
            await log("No locally modified pods found.", level: .info)
            return
        }
        
        await log("Found \(modifiedPods.count) pod(s) with local changes:", level: .info)
        for (podName, details) in modifiedPods.sorted(by: { $0.key < $1.key }) {
            await log("  \(podName): \(details.modificationReason)", level: .info)
        }
        
        let modifiedPodNames = Array(modifiedPods.keys)
        await log("Pods to switch to source: \(modifiedPodNames.sorted().joined(separator: ", "))", level: .info)
        
        // Switch only the modified pods back to source code
        try await switchModifiedPodsToSource(vault: vault, modifiedPodNames: modifiedPodNames)
        
        await log("✅ Successfully switched locally modified pods back to source code.", level: .result)
    }
    
    /// Finds all pods that have local modifications (either podspec changes or source code changes)
    private func findModifiedPods() async throws -> [String: PodModificationDetails] {
        let uncommittedFiles = try getUncommittedFiles()
        
        var modifiedPods: [String: PodModificationDetails] = [:]
        
        for file in uncommittedFiles {
            // Ignore external frameworks - these are remote dependencies, not local development pods
            if file.contains("ExternalFrameworks/") {
                continue
            }
            
            // Check if it's a podspec file
            if file.hasSuffix(".podspec") || file.hasSuffix(".podspec.json") {
                let podName = extractPodName(from: file)
                if let podName = podName {
                    let existing = modifiedPods[podName]
                    let newFiles = (existing?.modifiedFiles ?? []) + [file]
                    modifiedPods[podName] = PodModificationDetails(
                        modificationReason: "podspec modified",
                        modifiedFiles: newFiles
                    )
                }
            } else {
                // Check if the file is inside a pod directory structure
                if let podName = detectPodFromFilePath(file) {
                    let existing = modifiedPods[podName]
                    let newFiles = (existing?.modifiedFiles ?? []) + [file]
                    let reason = existing?.modificationReason ?? "source files modified"
                    modifiedPods[podName] = PodModificationDetails(
                        modificationReason: reason,
                        modifiedFiles: newFiles
                    )
                }
            }
        }
        
        return modifiedPods
    }
    
    /// Detects if a file path belongs to a pod and returns the pod name
    private func detectPodFromFilePath(_ filePath: String) -> String? {
        // Ignore external frameworks - these are remote dependencies, not local development pods
        if filePath.contains("ExternalFrameworks/") {
            return nil
        }
        
        // Common patterns for pod directory structures:
        // - services/CoreMobile/PodName/...
        // - services/PodName/...
        // - Pods/PodName/... (CocoaPods generated)
        // - LocalPods/PodName/...
        // - frameworks/PodName/...
        // - modules/PodName/...
        
        let pathComponents = filePath.split(separator: "/")
        
        // Look for common pod directory patterns
        for (index, component) in pathComponents.enumerated() {
            let componentStr = String(component)
            
            // Check if this looks like a pod container directory (excluding ExternalFrameworks)
            if ["services", "frameworks", "modules", "LocalPods", "Pods"].contains(componentStr) {
                // Handle nested structures like services/CoreMobile/PodName
                if componentStr == "services" && index + 2 < pathComponents.count {
                    let middleComponent = String(pathComponents[index + 1])
                    if middleComponent == "CoreMobile" {
                        let potentialPodName = String(pathComponents[index + 2])
                        if !["Sources", "Tests", "Resources", "Example", "Demo"].contains(potentialPodName) {
                            return potentialPodName
                        }
                    }
                }
                
                // Standard pattern: services/PodName, frameworks/PodName, etc.
                if index + 1 < pathComponents.count {
                    let potentialPodName = String(pathComponents[index + 1])
                    // Skip common non-pod directories
                    if !["Sources", "Tests", "Resources", "Example", "Demo", "CoreMobile"].contains(potentialPodName) {
                        return potentialPodName
                    }
                }
            }
            
            // Also check for direct pod names that might have a podspec nearby
            // Look for patterns like: PodName/Sources/..., PodName/Tests/...
            if ["Sources", "Tests", "Resources", "Classes", "Pod"].contains(componentStr) && index > 0 {
                let potentialPodName = String(pathComponents[index - 1])
                // Check if there might be a podspec file for this pod
                if !["src", "test", "main", "Example", "Demo", "CoreMobile"].contains(potentialPodName) {
                    return potentialPodName
                }
            }
        }
        
        return nil
    }
    
    /// Extracts pod names from podspec file paths
    private func extractPodNames(from podspecFiles: [String]) -> [String] {
        return podspecFiles.compactMap { file -> String? in
            return extractPodName(from: file)
        }
    }
    
    /// Extracts pod name from a single podspec file path
    private func extractPodName(from podspecFile: String) -> String? {
        let filename = URL(fileURLWithPath: podspecFile).lastPathComponent
        if filename.hasSuffix(".podspec.json") {
            return String(filename.dropLast(13)) // Remove ".podspec.json"
        } else if filename.hasSuffix(".podspec") {
            return String(filename.dropLast(8)) // Remove ".podspec"
        }
        return nil
    }
    
    /// Switches the specified modified pods back to source code while keeping other pods cached
    /// Uses existing Rollback and Use commands to reuse established functionality
    private func switchModifiedPodsToSource(vault: Vault, modifiedPodNames: [String]) async throws {
        await log("Switching modified pods back to source code while keeping other pods cached", level: .info)
        
        // Step 1: Use the existing Rollback command to restore original project state
        try await log("Restoring original project state") {
            try await dependencies.backupManager().asyncRestore(.original)
            dependencies.xcode.resetProjectsCache()
        }
        
        // Step 2: Use the existing Use command functionality to selectively apply binaries
        // Combine modified pod names with user's --except parameter
        let allExcludedPods = modifiedPodNames + except
        
        if !except.isEmpty {
            await log("Excluding modified pods (\(modifiedPodNames.joined(separator: ", "))) and user-specified pods (\(except.joined(separator: ", ")))", level: .info)
        } else {
            await log("Excluding only modified pods (\(modifiedPodNames.joined(separator: ", ")))", level: .info)
        }
        
        // Step 3: Apply binaries to all targets except the excluded ones using existing Use command logic
        try await log("Reapplying binaries for unmodified pods") {
            // Create TargetsOptions that excludes modified pods (keeping them as source)
            let targetsOptions = try RugbyFoundation.TargetsOptions(
                tryMode: false,
                targetsRegex: try NSRegularExpression(pattern: ".*"), // All targets
                exceptTargetsRegex: regex(patterns: [], exactMatches: allExcludedPods) // Except modified pods and user exclusions
            )
            
            // Use the existing Use command functionality
            try await dependencies.useBinariesManager().use(
                targetsOptions: targetsOptions,
                xcargs: dependencies.xcargsProvider.xcargs(strip: false),
                deleteSources: false
            )
        }
        
        await log("✅ Modified pods (\(modifiedPodNames.joined(separator: ", "))) are now using source code", level: .info)
        if !except.isEmpty {
            await log("✅ User-specified exclusions (\(except.joined(separator: ", "))) remain in source mode", level: .info)
        }
        await log("✅ All other pods remain cached for optimal build performance", level: .info)
    }
    
    /// Gets uncommitted files using the shell executor directly
    private func getUncommittedFiles() throws -> [String] {
        guard let output = try dependencies.shellExecutor.throwingShell("git status --porcelain") else {
            return []
        }
        return output.isEmpty ? [] : output.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count > 3 else { return nil }
            // Skip the first 3 characters (status flags and space) to get the filename
            return String(trimmed.dropFirst(3))
        }
    }
}

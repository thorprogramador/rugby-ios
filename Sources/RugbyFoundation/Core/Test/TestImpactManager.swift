import Foundation

// MARK: - Interface

/// The protocol describing a manager to analyse test targets in CocoaPods project.
public protocol ITestImpactManager: AnyObject {
    /// Prints affected test targets.
    /// - Parameters:
    ///   - targetsOptions: A set of options to to select targets.
    ///   - options: Xcode build options.
    ///   - baseCommit: Optional base commit to compare changes against (e.g., develop, main, or a specific commit hash).
    func impact(targetsOptions: TargetsOptions,
                buildOptions: XcodeBuildOptions,
                baseCommit: String?) async throws

    /// Marks test targets as passed.
    /// - Parameters:
    ///   - targetsOptions: A set of options to to select targets.
    ///   - options: Xcode build options.
    ///   - upToDateBranch: Skip if the current branch is not up-to-date to target one.
    func markAsPassed(targetsOptions: TargetsOptions,
                      buildOptions: XcodeBuildOptions,
                      upToDateBranch: String?) async throws
}

// MARK: - Implementation

final class TestImpactManager: Loggable {
    let logger: ILogger
    private let environmentCollector: IEnvironmentCollector
    private let rugbyXcodeProject: IRugbyXcodeProject
    private let buildTargetsManager: IBuildTargetsManager
    private let targetsHasher: ITargetsHasher
    private let testsStorage: ITestsStorage
    private let git: IGit
    private let targetsPrinter: ITargetsPrinter
    
    // Relevant file extensions for impact analysis
    private let relevantExtensions = [".swift", ".h", ".m", ".mm", ".c", ".cpp", ".podspec", ".xcconfig"]

    init(logger: ILogger,
         environmentCollector: IEnvironmentCollector,
         rugbyXcodeProject: IRugbyXcodeProject,
         buildTargetsManager: IBuildTargetsManager,
         targetsHasher: ITargetsHasher,
         testsStorage: ITestsStorage,
         git: IGit,
         targetsPrinter: ITargetsPrinter) {
        self.logger = logger
        self.environmentCollector = environmentCollector
        self.rugbyXcodeProject = rugbyXcodeProject
        self.buildTargetsManager = buildTargetsManager
        self.targetsHasher = targetsHasher
        self.testsStorage = testsStorage
        self.git = git
        self.targetsPrinter = targetsPrinter
    }
}

protocol IInternalTestImpactManager: ITestImpactManager {
    func fetchTestTargets(targetsOptions: TargetsOptions,
                          buildOptions: XcodeBuildOptions,
                          quiet: Bool) async throws -> TargetsMap
    func missingTargets(targetsOptions: TargetsOptions,
                        buildOptions: XcodeBuildOptions,
                        baseCommit: String?,
                        quiet: Bool) async throws -> TargetsMap
}

extension TestImpactManager: IInternalTestImpactManager {
    /// Finds impacted tests based on changes between the base commit and HEAD
    /// - Parameters:
    ///   - targets: Map of available test targets
    ///   - baseCommit: Base commit to compare against (e.g., develop, main, or a specific hash)
    ///   - buildOptions: Xcode build options
    ///   - quiet: If true, reduces log output
    /// - Returns: Map of impacted test targets
    private func findImpactedTestsFromBaseCommit(
        targets: TargetsMap,
        baseCommit: String,
        buildOptions: XcodeBuildOptions,
        quiet: Bool
    ) async throws -> TargetsMap {
        // Get changed files since the base commit
        let changedFiles = try await log(
            "Finding Changed Files from \(baseCommit)",
            level: quiet ? .info : .compact,
            auto: try git.changedFiles(from: baseCommit)
        )
        
        if changedFiles.isEmpty {
            await log("No Changed Files Found", level: quiet ? .info : .compact)
            return [:]
        }
        
        // Filter only relevant files (source code, podspecs, etc.)
        let relevantChangedFiles = changedFiles.filter { file in
            relevantExtensions.contains { file.hasSuffix($0) }
        }
        
        if relevantChangedFiles.isEmpty {
            await log("No Relevant Changed Files Found", level: quiet ? .info : .compact)
            return [:]
        }
        
        await log("Found \(relevantChangedFiles.count) Changed Files", level: quiet ? .info : .compact) {
            for file in relevantChangedFiles.sorted() {
                await log("\(file)", level: quiet ? .info : .info)
            }
        }
        
        // Determine which targets are affected by the changes
        let impactedTargets = try await determineImpactedTargets(targets: targets, changedFiles: relevantChangedFiles, quiet: quiet)
        
        if impactedTargets.isEmpty {
            await log("No Test Targets Impacted", level: quiet ? .info : .compact)
            return [:]
        }
        
        await log("Impacted Test Targets (\(impactedTargets.count))", level: quiet ? .info : .compact) {
            for target in impactedTargets.caseInsensitiveSortedByName() {
                await log("\(target.name)", level: quiet ? .info : .result)
            }
        }
        
        return impactedTargets
    }
    
    /// Determines which test targets are impacted by changed files
    /// - Parameters:
    ///   - targets: Map of available test targets
    ///   - changedFiles: List of changed files
    ///   - quiet: If true, reduces log output
    /// - Returns: Map of impacted test targets
    private func determineImpactedTargets(
        targets: TargetsMap,
        changedFiles: [String],
        quiet: Bool
    ) async throws -> TargetsMap {
        var impactedTargets = TargetsMap()
        let podspecChanges = changedFiles.filter { $0.hasSuffix(".podspec") }
        
        // If there are podspec changes, all tests that depend on those pods are impacted
        if !podspecChanges.isEmpty {
            await log("Found Podspec Changes", level: quiet ? .info : .compact)
            
            // Extract pod names from podspec files
            let changedPods = podspecChanges.compactMap { file -> String? in
                let filename = URL(fileURLWithPath: file).lastPathComponent
                guard filename.hasSuffix(".podspec") else { return nil }
                return String(filename.dropLast(8)) // Remove ".podspec"
            }
            
            // Add all test targets that depend on the changed pods
            for target in targets.values where target.isTests {
                let dependencies = target.explicitDependencies
                
                for pod in changedPods {
                    if dependencies.contains(where: { $0.key.lowercased() == pod.lowercased() }) {
                        impactedTargets[target.uuid] = target
                        break
                    }
                }
            }
        }
        
        // For source code file changes, we need to analyze which targets contain those files
        let sourceChanges = changedFiles.filter { file in
            file.hasSuffix(".swift") || file.hasSuffix(".h") || file.hasSuffix(".m") || 
            file.hasSuffix(".mm") || file.hasSuffix(".c") || file.hasSuffix(".cpp")
        }
        
        if !sourceChanges.isEmpty && impactedTargets.count < targets.count {
            // Here we would need to analyze each target to see if it contains the changed files
            // For simplicity, if there are source file changes and we couldn't determine exactly which targets
            // are affected, we mark all targets as impacted
            // In a more sophisticated implementation, we could analyze the file structure of each target
            
            // For now, if we already have targets impacted by podspec changes, we only use those
            // Otherwise, we consider all targets as impacted
            if impactedTargets.isEmpty {
                await log("Source File Changes Detected - Marking All Test Targets as Impacted", level: quiet ? .info : .compact)
                impactedTargets = targets
            }
        }
        
        return impactedTargets
    }
    
    func fetchTestTargets(targetsOptions: TargetsOptions,
                          buildOptions: XcodeBuildOptions,
                          quiet: Bool) async throws -> TargetsMap {
        let targets = try await log(
            "Finding Targets",
            level: quiet ? .info : .compact,
            auto: await buildTargetsManager.findTargets(
                targetsOptions.targetsRegex,
                exceptTargets: targetsOptions.exceptTargetsRegex,
                includingTests: true
            )
        )
        if targetsOptions.tryMode { return targets }
        try await log("Hashing Targets",
                      level: quiet ? .info : .compact,
                      auto: await targetsHasher.hash(targets, xcargs: buildOptions.xcargs))
        return targets.filter(\.value.isTests)
    }

    func missingTargets(targetsOptions: TargetsOptions,
                        buildOptions: XcodeBuildOptions,
                        baseCommit: String?,
                        quiet: Bool) async throws -> TargetsMap {
        let targets = try await fetchTestTargets(
            targetsOptions: targetsOptions,
            buildOptions: buildOptions,
            quiet: quiet
        )
        
        if let baseCommit = baseCommit {
            // Si se proporciona un commit base, utilizamos ese commit para determinar los cambios
            return try await findImpactedTestsFromBaseCommit(targets: targets, baseCommit: baseCommit, buildOptions: buildOptions, quiet: quiet)
        } else {
            // Comportamiento original: usar el almacenamiento de pruebas para encontrar pruebas faltantes
            return try await testsStorage.findMissingTests(of: targets, buildOptions: buildOptions)
        }
    }
}

extension TestImpactManager: ITestImpactManager {
    func impact(targetsOptions: TargetsOptions,
                buildOptions: XcodeBuildOptions,
                baseCommit: String? = nil) async throws {
        try await environmentCollector.logXcodeVersion()
        guard try await !rugbyXcodeProject.isAlreadyUsingRugby() else { throw RugbyError.alreadyUseRugby }

        let targets = try await fetchTestTargets(
            targetsOptions: targetsOptions,
            buildOptions: buildOptions,
            quiet: false
        )
        if targetsOptions.tryMode {
            return await targetsPrinter.print(targets)
        }

        let missingTestTargets = try await missingTargets(
            targetsOptions: targetsOptions,
            buildOptions: buildOptions,
            baseCommit: baseCommit,
            quiet: false
        )
        guard !missingTestTargets.isEmpty else {
            await log("No Affected Test Targets")
            return
        }

        await log("Affected Test Targets (\(missingTestTargets.count))") {
            for target in missingTestTargets.caseInsensitiveSortedByName() {
                guard let hash = target.hash else { continue }
                await log("\(target.name) (\(hash))", level: .result)
            }
        }
    }

    func markAsPassed(targetsOptions: TargetsOptions,
                      buildOptions: XcodeBuildOptions,
                      upToDateBranch: String?) async throws {
        if let branch = upToDateBranch {
            guard try !git.hasUncommittedChanges() else {
                return await log("Skip: The current branch has uncommitted changes.")
            }
            guard try !git.isBehind(branch: branch) else {
                return await log("Skip: The current branch is behind \(branch).")
            }
        }
        try await environmentCollector.logXcodeVersion()
        guard try await !rugbyXcodeProject.isAlreadyUsingRugby() else { throw RugbyError.alreadyUseRugby }

        let targets = try await fetchTestTargets(
            targetsOptions: targetsOptions,
            buildOptions: buildOptions,
            quiet: false
        )
        if targetsOptions.tryMode {
            return await targetsPrinter.print(targets)
        }
        try await log(
            "Marking Tests as Passed",
            auto: await testsStorage.saveTests(of: targets, buildOptions: buildOptions)
        )
    }
}

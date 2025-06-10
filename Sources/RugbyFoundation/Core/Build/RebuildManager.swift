import Foundation

// MARK: - Interface

/// The protocol describing a manager to rebuild specific podspecs in a CocoaPods project.
public protocol IRebuildManager: AnyObject {
    /// Rebuilds specific podspecs in a CocoaPods project and caches the binaries.
    /// - Parameters:
    ///   - targetsOptions: A set of options to select targets.
    ///   - options: Xcode build options.
    ///   - paths: A collection of Xcode paths.
    ///   - ignoreCache: A flag to ignore already built binaries.
    func rebuild(targetsOptions: TargetsOptions,
                options: XcodeBuildOptions,
                paths: XcodeBuildPaths,
                ignoreCache: Bool) async throws
}

// MARK: - Implementation

final class RebuildManager: Loggable {
    let logger: ILogger
    private let buildTargetsManager: IBuildTargetsManager
    private let librariesPatcher: ILibrariesPatcher
    private let xcodeProject: IInternalXcodeProject
    private let rugbyXcodeProject: IRugbyXcodeProject
    private let backupManager: IBackupManager
    private let processMonitor: IProcessMonitor
    private let xcodeBuild: IXcodeBuild
    private let binariesStorage: IBinariesStorage
    private let targetsHasher: ITargetsHasher
    private let useBinariesManager: IUseBinariesManager
    private let binariesCleaner: IBinariesCleaner
    private let environmentCollector: IEnvironmentCollector
    private let env: IEnvironment
    private let targetTreePainter: ITargetTreePainter
    private let targetsPrinter: ITargetsPrinter

    init(logger: ILogger,
         buildTargetsManager: IBuildTargetsManager,
         librariesPatcher: ILibrariesPatcher,
         xcodeProject: IInternalXcodeProject,
         rugbyXcodeProject: IRugbyXcodeProject,
         backupManager: IBackupManager,
         processMonitor: IProcessMonitor,
         xcodeBuild: IXcodeBuild,
         binariesStorage: IBinariesStorage,
         targetsHasher: ITargetsHasher,
         useBinariesManager: IUseBinariesManager,
         binariesCleaner: IBinariesCleaner,
         environmentCollector: IEnvironmentCollector,
         env: IEnvironment,
         targetTreePainter: ITargetTreePainter,
         targetsPrinter: ITargetsPrinter) {
        self.logger = logger
        self.buildTargetsManager = buildTargetsManager
        self.librariesPatcher = librariesPatcher
        self.xcodeProject = xcodeProject
        self.rugbyXcodeProject = rugbyXcodeProject
        self.backupManager = backupManager
        self.processMonitor = processMonitor
        self.xcodeBuild = xcodeBuild
        self.binariesStorage = binariesStorage
        self.targetsHasher = targetsHasher
        self.useBinariesManager = useBinariesManager
        self.binariesCleaner = binariesCleaner
        self.environmentCollector = environmentCollector
        self.env = env
        self.targetTreePainter = targetTreePainter
        self.targetsPrinter = targetsPrinter
    }

    private func prepareRebuild(targets: TargetsScope,
                              targetsTryMode: Bool) async throws -> TargetsMap {
        // For rebuild operations on projects already using Rugby, we need to temporarily restore
        // source targets to find the ones we want to rebuild
        let isUsingRugby = try await rugbyXcodeProject.isAlreadyUsingRugby()
        if isUsingRugby {
            try await log("Temporarily Restoring Source Targets", auto: await backupManager.asyncRestore(.original))
            xcodeProject.resetCache()
        }
        
        // Extract the regex patterns from TargetsScope
        let exactTargets: TargetsMap
        switch targets {
        case let .exact(targets):
            exactTargets = buildTargetsManager.filterTargets(targets)
        case let .filter(regex, exceptRegex):
            // For rebuild, we only want the exact target that matches, not its dependencies
            // Dependencies should already have binaries from previous builds
            let allTargets = try await xcodeProject.findTargets(by: regex, except: exceptRegex, includingDependencies: false)
            exactTargets = await log("Finding Targets", auto: buildTargetsManager.filterTargets(allTargets))
        }
        
        await log("Target Tree", level: .info, block: {
            await log(targetTreePainter.paint(targets: exactTargets), level: .info)
        })
        
        if targetsTryMode { return exactTargets }
        guard exactTargets.isNotEmpty else { throw BuildError.cantFindBuildTargets }

        try await log("Checking Binaries Storage", auto: await binariesCleaner.freeSpace())
        try await log("Patching Libraries", auto: await librariesPatcher.patch(exactTargets))
        
        return exactTargets
    }

    private func rebuildTargets(
        targets: TargetsMap,
        options: XcodeBuildOptions,
        paths: XcodeBuildPaths
    ) async throws {
        try await log("Hashing Targets", auto: await targetsHasher.hash(targets, xcargs: options.xcargs))

        let buildTarget = try await log("Creating Build Target",
                                        auto: await buildTargetsManager.createTarget(dependencies: targets))
        try await log("Saving Project", auto: await xcodeProject.save())

        let dependenciesCount = buildTarget.explicitDependencies.count
        let title = "Rebuild \(options.config): \(options.sdk.string)-\(options.arch) (\(dependenciesCount))"
        await log(
            "\(title)\n\(buildTarget.explicitDependencies.values.map { "* \($0.name)" }.sorted().joined(separator: "\n"))",
            level: .info
        )

        try await log(title, metricKey: "xcodebuild", level: .result, block: { [weak self] in
            guard let self else { return }

            let cleanup = {
                try? self.backupManager.restore(.tmp)
                self.xcodeProject.resetCache()
            }
            let processInterruptionTask = processMonitor.runOnInterruption(cleanup)

            do {
                try await xcodeBuild.build(target: buildTarget.name, options: options, paths: paths)
                processInterruptionTask.cancel()
                await log("Cleaning Up", block: cleanup)
            } catch {
                processInterruptionTask.cancel()
                await log("Cleaning Up", block: cleanup)
                throw error
            }
        })

        try await log(
            "Saving binaries (\(buildTarget.explicitDependencies.count))",
            auto: await binariesStorage.saveBinaries(ofTargets: buildTarget.explicitDependencies,
                                                     buildOptions: options,
                                                     buildPaths: paths)
        )
        
        // For rebuild operations, we need to restore the full Rugby state by reapplying all available binaries
        // We do this carefully to handle cases where some targets may not exist in the current project
        do {
            // First, find all current targets in the project
            let allTargets = try await buildTargetsManager.findTargets(nil, exceptTargets: nil)
            let (availableBinaries, _) = try binariesStorage.findBinaries(ofTargets: allTargets, buildOptions: options)
            
            if availableBinaries.isNotEmpty {
                try await log("Reapplying All Available Binaries (\(availableBinaries.count))", 
                             auto: await useBinariesManager.use(targets: availableBinaries, keepGroups: true))
                try await rugbyXcodeProject.markAsUsingRugby()
            }
        } catch {
            // If reapplying binaries fails (e.g., due to missing targets), just mark as using Rugby
            // The rebuilt targets are already available as binaries
            await log("Warning: Could not reapply all binaries, but rebuild completed successfully", level: .info)
            try await rugbyXcodeProject.markAsUsingRugby()
        }
        
        try await log("Saving Project", auto: await xcodeProject.save())
        xcodeProject.resetCache()
    }
}

// MARK: - IRebuildManager

extension RebuildManager: IRebuildManager {
    public func rebuild(targetsOptions: TargetsOptions,
                      options: XcodeBuildOptions,
                      paths: XcodeBuildPaths,
                      ignoreCache: Bool) async throws {
        try await environmentCollector.logXcodeVersion()
        
        // Check if project is using Rugby to determine workflow
        let isUsingRugby = try await rugbyXcodeProject.isAlreadyUsingRugby()
        
        if isUsingRugby {
            // For projects already using Rugby, we need to create a temporary backup first
            // so we can restore source targets for the rebuild process
            try await log("Backing up Current State", auto: await backupManager.backup(xcodeProject, kind: .tmp))
        }
        
        let exactTargets = try await prepareRebuild(
            targets: .init(targetsOptions),
            targetsTryMode: targetsOptions.tryMode
        )
        
        if targetsOptions.tryMode {
            if isUsingRugby {
                // Restore the Rugby state if we're in try mode
                try await backupManager.asyncRestore(.tmp)
                xcodeProject.resetCache()
            }
            return await targetsPrinter.print(exactTargets)
        }
        
        try await rebuildTargets(
            targets: exactTargets,
            options: options,
            paths: paths
        )
    }
}

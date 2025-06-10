import ArgumentParser
import Fish
import RugbyFoundation

struct Shortcuts: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "shortcuts",
        abstract: "Set of base commands combinations.",
        discussion: Links.commandsHelp("shortcuts.md"),
        subcommands: [Umbrella.self, Cache.self, RebuildCache.self],
        defaultSubcommand: Umbrella.self
    )
}

extension Shortcuts {
    struct Umbrella: AsyncParsableCommand, AnyArgumentsCommand {
        static var configuration = CommandConfiguration(
            commandName: "umbrella",
            abstract: """
            Run the \("plan".accent) command if plans file exists \
            or run the \("cache".accent) command.
            """,
            discussion: Links.commandsHelp("shortcuts/umbrella.md")
        )

        @Argument(help: "Any arguments of \("plan".accent) or \("cache".accent) commands.")
        var arguments: [String] = []

        func run() async throws {
            try await body()
        }
    }
}

extension Shortcuts.Umbrella: RunnableCommand {
    func body() async throws {
        let plansPath: String
        if let pathIndex = arguments.firstIndex(where: { $0 == "--path" || $0 == "-p" }),
           arguments.count > pathIndex + 1 {
            plansPath = arguments[pathIndex + 1]
        } else {
            plansPath = dependencies.router.plansRelativePath
        }

        let parsedCommand: ParsableCommand
        if File.isExist(at: Folder.current.subpath(plansPath)) {
            parsedCommand = try Plan.parseAsRoot(arguments)
        } else {
            parsedCommand = try Shortcuts.Cache.parseAsRoot(arguments)
        }
        var runnableCommand = try parsedCommand.toRunnable()
        try await runnableCommand.run()
    }
}

// MARK: - Cache Subcommand

extension Shortcuts {
    struct Cache: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "cache",
            abstract: "Run the \("build".accent) and \("use".accent) commands.",
            discussion: Links.commandsHelp("shortcuts/cache.md")
        )

        @Flag(name: .shortAndLong, help: "Restore projects state before the last Rugby usage.")
        var rollback = false

        @Flag(name: .long, help: "Prebuild targets ignoring sources.")
        var prebuild = false

        @OptionGroup
        var buildOptions: BuildOptions

        @Option(name: .long, help: "Path to xcresult bundle.")
        var resultBundlePath: String?

        @Flag(name: .long, help: "Ignore shared cache.")
        var ignoreCache = false

        @Flag(name: .long, help: "Delete target groups from project.")
        var deleteSources = false

        @Option(help: "Warmup cache with this endpoint.")
        var warmup: String?

        @Option(help: "Extra HTTP header fields for warmup (\"s3-key: my-secret-key\").")
        var headers: [String] = []

        @Option(help: "The maximum number of simultaneous connections.")
        var maxConnections = settings.warmupMaximumConnectionsPerHost

        @Option(help: "Binary archive file type to use: zip or 7z.")
        var archiveType: RugbyFoundation.ArchiveType = .zip

        @OptionGroup
        var commonOptions: CommonOptions

        func run() async throws {
            try await run(body,
                          outputType: commonOptions.output,
                          logLevel: commonOptions.logLevel)
        }
    }
}

extension Shortcuts.Cache: RunnableCommand {
    func body() async throws {
        do {
            // Check if the project is already using Rugby
            // Check if the project is already using Rugby by using the buildManager
            // The buildManager.build method throws RugbyError.alreadyUseRugby if the project is already using Rugby
            let buildManager = dependencies.buildManager()
            
            // Try to check if project is using Rugby - if it throws alreadyUseRugby error, then it is
            var isUsingRugby = false
            do {
                // Just create a dummy task that would fail if project is using Rugby
                try await buildManager.build(
                    targetsOptions: RugbyFoundation.TargetsOptions(),
                    options: RugbyFoundation.XcodeBuildOptions(
                        sdk: .sim,
                        config: "Debug",
                        arch: "arm64",
                        xcargs: [],
                        resultBundlePath: nil
                    ),
                    paths: try dependencies.xcode.paths(),
                    ignoreCache: false
                )
            } catch let error where error.localizedDescription.contains("already using") {
                isUsingRugby = true
            } catch {
                // Other errors are not relevant for our check
            }
            
            if isUsingRugby && !rollback {
                await log("Project is already using Rugby. Switching to rebuild-cache mode.", level: .info)
                
                // Instead of directly executing the RebuildCache command, we run
                // the same commands that RebuildCache uses but in our context
                var runnableCommands: [(name: String, RunnableCommand)] = []
                
                // Configure the Rebuild command (equivalent to Build.Rebuild in RebuildCache)
                var rebuild = Build.Rebuild()
                rebuild.buildOptions = buildOptions
                rebuild.ignoreCache = ignoreCache
                rebuild.resultBundlePath = resultBundlePath
                rebuild.commonOptions = commonOptions
                runnableCommands.append(("Rebuild", rebuild))
                
                // Configure the Use command (same as in RebuildCache)
                var use = Use()
                use.deleteSources = deleteSources
                use.targetsOptions = buildOptions.targetsOptions
                use.additionalBuildOptions = buildOptions.additionalBuildOptions
                use.commonOptions = commonOptions
                runnableCommands.append(("Use", use))
                
                // Execute the commands
                for (name, command) in runnableCommands {
                    try await log(name.green) {
                        try await command.body()
                    }
                }
                
                return
            }
        } catch {
            // If there's an error checking Rugby status, continue with normal flow
            // but log the error for diagnostics
            await log("Error checking if project is using Rugby: \(error). Continuing with normal cache flow.", level: .info)
        }
        
        // Normal cache flow if project is not using Rugby
        var runnableCommands: [(name: String, RunnableCommand)] = []

        if rollback {
            var rollback = Rollback()
            rollback.commonOptions = commonOptions
            runnableCommands.append(("Rollback", rollback))
        }

        if prebuild {
            var prebuild = Build.Pre()
            prebuild.buildOptions = buildOptions
            prebuild.commonOptions = commonOptions
            runnableCommands.append(("Prebuild", prebuild))
        }

        if let endpoint = warmup {
            var warmup = Warmup()
            warmup.endpoint = endpoint
            warmup.analyse = false
            warmup.buildOptions = buildOptions
            warmup.commonOptions = commonOptions
            warmup.timeout = Self.settings.warmupTimeout
            warmup.maxConnections = maxConnections
            warmup.headers = headers
            warmup.archiveType = archiveType
            runnableCommands.append(("Warmup", warmup))
        }

        var build = Build.Full()
        build.buildOptions = buildOptions
        build.ignoreCache = ignoreCache
        build.resultBundlePath = resultBundlePath
        build.commonOptions = commonOptions
        runnableCommands.append(("Build", build))

        var use = Use()
        use.deleteSources = deleteSources
        use.targetsOptions = buildOptions.targetsOptions
        use.additionalBuildOptions = buildOptions.additionalBuildOptions
        use.commonOptions = commonOptions
        runnableCommands.append(("Use", use))

        for (name, command) in runnableCommands {
            try await log(name.green) {
                try await command.body()
            }
        }
    }
}

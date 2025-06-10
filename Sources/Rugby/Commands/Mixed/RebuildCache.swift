import ArgumentParser
import Fish
import RugbyFoundation

extension Shortcuts {
    struct RebuildCache: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "rebuild-cache",
            abstract: "Rebuild and cache specific podspecs even when the project is already using Rugby.",
            discussion: "This command allows rebuilding and caching specific podspecs that have been modified locally."
        )

        @Flag(name: .shortAndLong, help: "Restore projects state before the last Rugby usage.")
        var rollback = false

        @OptionGroup
        var buildOptions: BuildOptions

        @Option(name: .long, help: "Path to xcresult bundle.")
        var resultBundlePath: String?

        @Flag(name: .long, help: "Ignore shared cache.")
        var ignoreCache = false

        @Flag(name: .long, help: "Delete target groups from project.")
        var deleteSources = false

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

extension Shortcuts.RebuildCache: RunnableCommand {
    func body() async throws {
        var runnableCommands: [(name: String, RunnableCommand)] = []

        if rollback {
            var rollback = Rollback()
            rollback.commonOptions = commonOptions
            runnableCommands.append(("Rollback", rollback))
        }

        var rebuild = Build.Rebuild()
        rebuild.buildOptions = buildOptions
        rebuild.ignoreCache = ignoreCache
        rebuild.resultBundlePath = resultBundlePath
        rebuild.commonOptions = commonOptions
        runnableCommands.append(("Rebuild", rebuild))

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

import ArgumentParser
import Fish
import RugbyFoundation

extension Build {
    struct Rebuild: AsyncParsableCommand, RunnableCommand {
        static var configuration = CommandConfiguration(
            commandName: "rebuild",
            abstract: "Rebuild and cache specific podspecs.",
            discussion: "Allows rebuilding specific podspecs even when the project is already using Rugby."
        )

        @OptionGroup
        var buildOptions: BuildOptions

        @Flag(name: .long, help: "Ignore shared cache.")
        var ignoreCache = false

        @Option(name: .long, help: "Path to xcresult bundle.")
        var resultBundlePath: String?

        @OptionGroup
        var commonOptions: CommonOptions

        func run() async throws {
            try await run(body,
                          outputType: commonOptions.output,
                          logLevel: commonOptions.logLevel)
        }

        func body() async throws {
            try await dependencies.rebuildManager().rebuild(
                targetsOptions: buildOptions.targetsOptions.foundation(),
                options: buildOptions.xcodeBuildOptions(resultBundlePath: resultBundlePath),
                paths: dependencies.xcode.paths(),
                ignoreCache: ignoreCache
            )
        }
    }
}

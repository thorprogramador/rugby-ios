import ArgumentParser

struct Test: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "_test",
        abstract: "\("(Experimental)".yellow) Analyse and run tests.",
        discussion: Links.commandsHelp("test.md"),
        subcommands: [Run.self, Impact.self, Passed.self],
        defaultSubcommand: Run.self
    )
}

private extension Test {
    struct Run: RunnableCommand {
        static var configuration = CommandConfiguration(
            commandName: "run",
            abstract: "\("(Experimental)".yellow) Run tests by impact or not.",
            discussion: Links.commandsHelp("test/run.md")
        )

        @Option(name: [.long, .customShort("n")], help: "A simulator name.")
        var simulatorName: String

        @Option(name: [.long, .customShort("p")], help: "A path to testplan template.")
        var testplanTemplatePath: String

        @Flag(name: .long, help: "Select tests by impact.")
        var impact = false

        @Option(name: .long, help: "Base commit to compare changes against (e.g., develop, main, or a specific commit hash).")
        var baseCommit: String?

        @Flag(name: .long, help: "Mark test targets as passed if all tests are succeed.")
        var pass = false

        @Option(name: .long, help: "Path to xcresult bundle.")
        var resultBundlePath: String?

        @OptionGroup
        var buildOptions: BuildOptions

        @OptionGroup
        var commonOptions: CommonOptions

        func run() async throws {
            try await run(body,
                          outputType: commonOptions.output,
                          logLevel: commonOptions.logLevel)
        }

        func body() async throws {
            try await dependencies.testManager().test(
                targetsOptions: buildOptions.targetsOptions.foundation(),
                buildOptions: buildOptions.xcodeBuildOptions(resultBundlePath: resultBundlePath),
                buildPaths: dependencies.xcode.paths(),
                testPaths: dependencies.xcode.paths(logsSubfolder: "test"),
                testplanTemplatePath: testplanTemplatePath,
                simulatorName: simulatorName,
                byImpact: impact,
                baseCommit: baseCommit,
                markPassed: pass
            )
        }
    }
}

private extension Test {
    struct Impact: RunnableCommand {
        static var configuration = CommandConfiguration(
            commandName: "impact",
            abstract: "\("(Experimental)".yellow) Print affected test targets.",
            discussion: Links.commandsHelp("test/impact.md")
        )
        
        @Option(name: .long, help: "Base commit to compare changes against (e.g., develop, main, or a specific commit hash).")
        var baseCommit: String?

        @OptionGroup
        var buildOptions: BuildOptions

        @OptionGroup
        var commonOptions: CommonOptions

        func run() async throws {
            try await run(body,
                          outputType: commonOptions.output,
                          logLevel: commonOptions.logLevel)
        }

        func body() async throws {
            try await dependencies.testImpactManager().impact(
                targetsOptions: buildOptions.targetsOptions.foundation(),
                buildOptions: buildOptions.xcodeBuildOptions(),
                baseCommit: baseCommit
            )
        }
    }
}

private extension Test {
    struct Passed: RunnableCommand {
        static var configuration = CommandConfiguration(
            commandName: "pass",
            abstract: "\("(Experimental)".yellow) Mark test targets as passed.",
            discussion: Links.commandsHelp("test/pass.md")
        )

        @Option(name: .shortAndLong, help: "Skip if the current branch is not up-to-date to \("target one".yellow).")
        var upToDateBranch: String?

        @OptionGroup
        var buildOptions: BuildOptions

        @OptionGroup
        var commonOptions: CommonOptions

        func run() async throws {
            try await run(body,
                          outputType: commonOptions.output,
                          logLevel: commonOptions.logLevel)
        }

        func body() async throws {
            try await dependencies.testImpactManager().markAsPassed(
                targetsOptions: buildOptions.targetsOptions.foundation(),
                buildOptions: buildOptions.xcodeBuildOptions(),
                upToDateBranch: upToDateBranch
            )
        }
    }
}

import Foundation

// MARK: - Interface

protocol IBuildTargetsManager: AnyObject {
    func findTargets(
        _ targets: NSRegularExpression?,
        exceptTargets: NSRegularExpression?,
        includingTests: Bool
    ) async throws -> TargetsMap

    func filterTargets(
        _ targets: TargetsMap,
        includingTests: Bool
    ) -> TargetsMap

    func createTarget(
        dependencies: TargetsMap,
        buildConfiguration: String?,
        testplanPath: String?
    ) async throws -> IInternalTarget
}

extension IBuildTargetsManager {
    func findTargets(
        _ targets: NSRegularExpression?,
        exceptTargets: NSRegularExpression?
    ) async throws -> TargetsMap {
        try await findTargets(targets, exceptTargets: exceptTargets, includingTests: false)
    }

    func filterTargets(_ targets: TargetsMap) -> TargetsMap {
        filterTargets(targets, includingTests: false)
    }

    func createTarget(dependencies: TargetsMap) async throws -> IInternalTarget {
        try await createTarget(dependencies: dependencies, buildConfiguration: nil, testplanPath: nil)
    }
}

// MARK: - Implementation

final class BuildTargetsManager {
    private let xcodeProject: IInternalXcodeProject
    private let buildTargetName = "RugbyPods"

    init(xcodeProject: IInternalXcodeProject) {
        self.xcodeProject = xcodeProject
    }
}

extension BuildTargetsManager: IBuildTargetsManager {
    func findTargets(
        _ targets: NSRegularExpression?,
        exceptTargets: NSRegularExpression?,
        includingTests: Bool
    ) async throws -> TargetsMap {
        let foundTargets = try await xcodeProject.findTargets(
            by: targets,
            except: exceptTargets,
            includingDependencies: true
        )
        return filterTargets(foundTargets, includingTests: includingTests)
    }

    func filterTargets(_ targets: TargetsMap, includingTests: Bool) -> TargetsMap {
        targets.filter { _, target in
            guard target.isNative, !target.isPodsUmbrella, !target.isApplication else { return false }
            
            // Exclude targets from dev_modules folder (development/testing modules)
            if target.name.contains("dev_modules") || target.name.hasPrefix("dev_modules") {
                return false
            }
            
            return includingTests || !target.isTests
        }
    }

    func createTarget(
        dependencies: TargetsMap,
        buildConfiguration: String?,
        testplanPath: String?
    ) async throws -> IInternalTarget {
        let target = try await xcodeProject.createAggregatedTargetInRootProject(
            name: buildTargetName,
            dependencies: dependencies
        )
        if let buildConfiguration, let testplanPath {
            xcodeProject.createTestingScheme(target, buildConfiguration: buildConfiguration, testplanPath: testplanPath)
        }
        return target
    }
}

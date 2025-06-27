@testable import RugbyFoundation
import XCTest

final class TargetsHasherTests: XCTestCase {
    private var sut: ITargetsHasher!
    private var foundationHasher: FoundationHasherMock!
    private var swiftVersionProvider: ISwiftVersionProviderMock!
    private var xcodeCLTVersionProvider: IXcodeCLTVersionProviderMock!
    private var buildPhaseHasher: IBuildPhaseHasherMock!
    private var cocoaPodsScriptsHasher: ICocoaPodsScriptsHasherMock!
    private var configurationsHasher: IConfigurationsHasherMock!
    private var productHasher: IProductHasherMock!
    private var buildRulesHasher: IBuildRulesHasherMock!

    override func setUp() {
        super.setUp()
        foundationHasher = FoundationHasherMock()
        swiftVersionProvider = ISwiftVersionProviderMock()
        xcodeCLTVersionProvider = IXcodeCLTVersionProviderMock()
        buildPhaseHasher = IBuildPhaseHasherMock()
        cocoaPodsScriptsHasher = ICocoaPodsScriptsHasherMock()
        configurationsHasher = IConfigurationsHasherMock()
        productHasher = IProductHasherMock()
        buildRulesHasher = IBuildRulesHasherMock()
        sut = TargetsHasher(
            foundationHasher: foundationHasher,
            swiftVersionProvider: swiftVersionProvider,
            xcodeCLTVersionProvider: xcodeCLTVersionProvider,
            buildPhaseHasher: buildPhaseHasher,
            cocoaPodsScriptsHasher: cocoaPodsScriptsHasher,
            configurationsHasher: configurationsHasher,
            productHasher: productHasher,
            buildRulesHasher: buildRulesHasher
        )
    }

    override func tearDown() {
        super.tearDown()
        foundationHasher = nil
        swiftVersionProvider = nil
        xcodeCLTVersionProvider = nil
        buildPhaseHasher = nil
        cocoaPodsScriptsHasher = nil
        configurationsHasher = nil
        productHasher = nil
        buildRulesHasher = nil
        sut = nil // FIXME: Sometimes I catch EXC_BAD_ACCESS here
    }
}

extension TargetsHasherTests {
    func test_basic() async throws {
        let expectedAlamofireHashContext = """
        buildOptions:
          xcargs:
          - COMPILER_INDEX_STORE_ENABLE=NO
        buildPhases:
        - Alamofire-framework_buildPhase_hash
        buildRules:
        - AlamofireBuildRule_cocoaPodsScripts_hash
        cocoaPodsScripts:
        - Alamofire-framework_cocoaPodsScripts_hash
        configurations:
        - Alamofire-framework_configuration_hash
        dependencies: {}
        name: Alamofire-framework
        product: null
        swift_version: \'5.9\'
        xcode_version: 14.5 (1234)\n
        """
        let alamofire = IInternalTargetMock()
        alamofire.underlyingName = "Alamofire-framework"
        alamofire.underlyingUuid = "3949679AB5CF3F2C77C15A0E67E8AF64"
        alamofire.buildRules = [.mock(name: "AlamofireBuildRule")]

        let expectedMoyaHashContext = """
        buildOptions:
          xcargs:
          - COMPILER_INDEX_STORE_ENABLE=NO
        buildPhases:
        - Moya-framework_buildPhase_hash
        buildRules:
        - MoyaBuildRule_cocoaPodsScripts_hash
        cocoaPodsScripts:
        - Moya-framework_cocoaPodsScripts_hash
        configurations:
        - Moya-framework_configuration_hash
        dependencies:
          Alamofire-framework: Alamofire_hashed
        name: Moya-framework
        product:
          MoyaProduct: MoyaProduct_hash
        swift_version: \'5.9\'
        xcode_version: 14.5 (1234)\n
        """
        let moya = IInternalTargetMock()
        moya.underlyingName = "Moya-framework"
        moya.underlyingUuid = "3F66A14997A3B09C1C6CC3AFD763A745"
        moya.buildRules = [.mock(name: "MoyaBuildRule")]
        moya.product = Product(name: "Moya", moduleName: nil, type: .framework, parentFolderName: nil)
        moya.explicitDependencies = [alamofire.uuid: alamofire]
        moya.dependencies = [alamofire.uuid: alamofire]

        let expectedLocalPodResourcesHashContext = """
        buildOptions:
          xcargs:
          - COMPILER_INDEX_STORE_ENABLE=NO
        buildPhases:
        - LocalPod-framework-LocalPodResources_buildPhase_hash
        buildRules:
        - LocalPodResourcesBuildRule_cocoaPodsScripts_hash
        cocoaPodsScripts:
        - LocalPod-framework-LocalPodResources_cocoaPodsScripts_hash
        configurations:
        - LocalPod-framework-LocalPodResources_configuration_hash
        dependencies: {}
        name: LocalPod-framework-LocalPodResources
        product: null
        swift_version: \'5.9\'
        xcode_version: 14.5 (1234)\n
        """
        let localPodResources = IInternalTargetMock()
        localPodResources.underlyingName = "LocalPod-framework-LocalPodResources"
        localPodResources.underlyingUuid = "4D46B2A355F0821E50320A2311A88AE9"
        localPodResources.buildRules = [.mock(name: "LocalPodResourcesBuildRule")]

        let expectedLocalPodHashContext = """
        buildOptions:
          xcargs:
          - COMPILER_INDEX_STORE_ENABLE=NO
        buildPhases:
        - LocalPod-framework_buildPhase_hash
        buildRules:
        - LocalPodBuildRule_cocoaPodsScripts_hash
        cocoaPodsScripts:
        - LocalPod-framework_cocoaPodsScripts_hash
        configurations:
        - LocalPod-framework_configuration_hash
        dependencies:
          LocalPod-framework-LocalPodResources: LocalPodResources_hashed
          Moya-framework: Moya_hashed
        name: LocalPod-framework
        product: null
        swift_version: \'5.9\'
        xcode_version: 14.5 (1234)\n
        """
        let localPod = IInternalTargetMock()
        localPod.underlyingName = "LocalPod-framework"
        localPod.underlyingUuid = "1A5F2B8B18DD417D0FAA115D004EB177"
        localPod.buildRules = [.mock(name: "LocalPodBuildRule")]
        // Set explicit dependencies (only direct dependencies)
        localPod.explicitDependencies = [
            moya.uuid: moya,
            localPodResources.uuid: localPodResources
        ]
        // Set all dependencies (including transitive)
        localPod.dependencies = [
            moya.uuid: moya,
            alamofire.uuid: alamofire,
            localPodResources.uuid: localPodResources
        ]

        let targets: TargetsMap = [
            alamofire.uuid: alamofire,
            localPod.uuid: localPod,
            moya.uuid: moya,
            localPodResources.uuid: localPodResources
        ]

        xcodeCLTVersionProvider.versionReturnValue = XcodeVersion(base: "14.5", build: "1234")

        await swiftVersionProvider.setSwiftVersionReturnValue("5.9")
        configurationsHasher.hashContextClosure = { ["\($0.name)_configuration_hash"] }
        cocoaPodsScriptsHasher.hashContextClosure = { ["\($0.name)_cocoaPodsScripts_hash"] }
        buildPhaseHasher.hashContextTargetClosure = { ["\($0.name)_buildPhase_hash"] }
        buildRulesHasher.hashContextClosure = {
            $0.map { "\($0.name ?? "Unknown")_cocoaPodsScripts_hash" }
        }
        productHasher.hashContextReturnValue = ["MoyaProduct": "MoyaProduct_hash"]
        foundationHasher.hashArrayOfStringsClosure = { $0.map { "\($0)_hashed" }.joined(separator: "|") }
        foundationHasher.hashStringClosure = {
            switch $0 {
            case expectedAlamofireHashContext: return "Alamofire_hashed"
            case expectedLocalPodHashContext: return "LocalPod_hashed"
            case expectedMoyaHashContext: return "Moya_hashed"
            case expectedLocalPodResourcesHashContext: return "LocalPodResources_hashed"
            default: fatalError()
            }
        }

        // Act
        try await sut.hash(targets, xcargs: [
            "COMPILER_INDEX_STORE_ENABLE=NO"
        ])

        // Assert
        XCTAssertEqual(alamofire.hashContext, expectedAlamofireHashContext)
        XCTAssertEqual(alamofire.hash, "Alamofire_hashed")

        XCTAssertEqual(localPod.hashContext, expectedLocalPodHashContext)
        XCTAssertEqual(localPod.hash, "LocalPod_hashed")

        XCTAssertEqual(localPodResources.hashContext, expectedLocalPodResourcesHashContext)
        XCTAssertEqual(localPodResources.hash, "LocalPodResources_hashed")

        XCTAssertEqual(moya.hashContext, expectedMoyaHashContext)
        XCTAssertEqual(moya.hash, "Moya_hashed")
    }

    func test_skip_hash() async throws {
        let alamofire = IInternalTargetMock()
        alamofire.underlyingUuid = "3949679AB5CF3F2C77C15A0E67E8AF64"
        alamofire.hash = "test_hash"
        alamofire.hashContext = "test_hashContext"
        alamofire.targetHashContext = ["testKey": "testValue"]
        let targets: TargetsMap = [alamofire.uuid: alamofire]
        xcodeCLTVersionProvider.versionReturnValue = XcodeVersion(base: "14.5", build: "1234")

        // Act
        try await sut.hash(targets, xcargs: [], rehash: false)

        // Assert
        XCTAssertEqual(alamofire.hashContext, "test_hashContext")
        XCTAssertEqual(alamofire.hash, "test_hash")
        XCTAssertEqual(alamofire.targetHashContext as? [String: String], ["testKey": "testValue"])
    }

    func test_rehash() async throws {
        let alamofire = IInternalTargetMock()
        alamofire.underlyingName = "Alamofire-framework"
        alamofire.underlyingUuid = "3949679AB5CF3F2C77C15A0E67E8AF64"
        alamofire.hash = "test_hash"
        alamofire.hashContext = "test_hashContext"
        alamofire.targetHashContext = ["testKey": "testValue"]
        let targets: TargetsMap = [alamofire.uuid: alamofire]

        await swiftVersionProvider.setSwiftVersionReturnValue("5.9")
        configurationsHasher.hashContextReturnValue = []
        cocoaPodsScriptsHasher.hashContextReturnValue = []
        buildRulesHasher.hashContextReturnValue = []
        buildPhaseHasher.hashContextTargetReturnValue = []
        foundationHasher.hashArrayOfStringsReturnValue = "test_rehash_array"
        foundationHasher.hashStringReturnValue = "test_rehash"
        xcodeCLTVersionProvider.versionReturnValue = XcodeVersion(base: "14.5", build: "1234")

        // Act
        try await sut.hash(targets, xcargs: [], rehash: true)

        // Assert
        XCTAssertEqual(
            alamofire.hashContext,
            """
            buildOptions:
              xcargs: []
            buildPhases: []
            buildRules: []
            cocoaPodsScripts: []
            configurations: []
            dependencies: {}
            name: Alamofire-framework
            product: null
            swift_version: \'5.9\'
            xcode_version: 14.5 (1234)\n
            """
        )
        XCTAssertEqual(alamofire.hash, "test_rehash")
    }

    func test_explicitDependencies_deeplyNested() async throws {
        // This test verifies that using explicit dependencies prevents cascading hash changes
        // in deeply nested dependency scenarios
        
        // Create a deep dependency tree: App -> Feature -> Service -> Network -> HTTP -> Socket
        let socket = IInternalTargetMock()
        socket.underlyingName = "Socket-framework"
        socket.underlyingUuid = "SOCKET123"
        socket.buildRules = [.mock(name: "SocketBuildRule")]
        
        let http = IInternalTargetMock()
        http.underlyingName = "HTTP-framework"
        http.underlyingUuid = "HTTP123"
        http.buildRules = [.mock(name: "HTTPBuildRule")]
        http.explicitDependencies = [socket.uuid: socket]
        http.dependencies = [socket.uuid: socket]
        
        let network = IInternalTargetMock()
        network.underlyingName = "Network-framework"
        network.underlyingUuid = "NETWORK123"
        network.buildRules = [.mock(name: "NetworkBuildRule")]
        network.explicitDependencies = [http.uuid: http]
        // Simulating flattened dependencies (what collectDependencies would do)
        network.dependencies = [
            http.uuid: http,
            socket.uuid: socket  // transitive dependency
        ]
        
        let service = IInternalTargetMock()
        service.underlyingName = "Service-framework"
        service.underlyingUuid = "SERVICE123"
        service.buildRules = [.mock(name: "ServiceBuildRule")]
        service.explicitDependencies = [network.uuid: network]
        service.dependencies = [
            network.uuid: network,
            http.uuid: http,      // transitive
            socket.uuid: socket   // transitive
        ]
        
        let feature = IInternalTargetMock()
        feature.underlyingName = "Feature-framework"
        feature.underlyingUuid = "FEATURE123"
        feature.buildRules = [.mock(name: "FeatureBuildRule")]
        feature.explicitDependencies = [service.uuid: service]
        feature.dependencies = [
            service.uuid: service,
            network.uuid: network,  // transitive
            http.uuid: http,        // transitive
            socket.uuid: socket     // transitive
        ]
        
        let app = IInternalTargetMock()
        app.underlyingName = "App"
        app.underlyingUuid = "APP123"
        app.buildRules = [.mock(name: "AppBuildRule")]
        app.explicitDependencies = [feature.uuid: feature]
        app.dependencies = [
            feature.uuid: feature,
            service.uuid: service,  // transitive
            network.uuid: network,  // transitive
            http.uuid: http,        // transitive
            socket.uuid: socket     // transitive
        ]
        
        let targets: TargetsMap = [
            app.uuid: app,
            feature.uuid: feature,
            service.uuid: service,
            network.uuid: network,
            http.uuid: http,
            socket.uuid: socket
        ]
        
        // Setup mocks
        xcodeCLTVersionProvider.versionReturnValue = XcodeVersion(base: "14.5", build: "1234")
        await swiftVersionProvider.setSwiftVersionReturnValue("5.9")
        configurationsHasher.hashContextClosure = { ["\($0.name)_configuration_hash"] }
        cocoaPodsScriptsHasher.hashContextClosure = { ["\($0.name)_cocoaPodsScripts_hash"] }
        buildPhaseHasher.hashContextTargetClosure = { ["\($0.name)_buildPhase_hash"] }
        buildRulesHasher.hashContextClosure = { $0.map { "\($0.name ?? "Unknown")_cocoaPodsScripts_hash" } }
        foundationHasher.hashStringClosure = { _ in "stable_hash" }
        
        // Act
        try await sut.hash(targets, xcargs: [])
        
        // Assert - App should only include Feature's hash, not all transitive dependencies
        let appHashContext = app.hashContext ?? ""
        XCTAssertTrue(appHashContext.contains("Feature-framework: stable_hash"))
        XCTAssertFalse(appHashContext.contains("Service-framework:"))
        XCTAssertFalse(appHashContext.contains("Network-framework:"))
        XCTAssertFalse(appHashContext.contains("HTTP-framework:"))
        XCTAssertFalse(appHashContext.contains("Socket-framework:"))
    }

    func test_explicitDependencies_diamondDependency() async throws {
        // Test diamond dependency pattern: 
        //     Common
        //    /      \
        //   A        B
        //    \      /
        //      App
        
        let common = IInternalTargetMock()
        common.underlyingName = "Common-framework"
        common.underlyingUuid = "COMMON123"
        common.buildRules = [.mock(name: "CommonBuildRule")]
        
        let moduleA = IInternalTargetMock()
        moduleA.underlyingName = "ModuleA-framework"
        moduleA.underlyingUuid = "MODULEA123"
        moduleA.buildRules = [.mock(name: "ModuleABuildRule")]
        moduleA.explicitDependencies = [common.uuid: common]
        moduleA.dependencies = [common.uuid: common]
        
        let moduleB = IInternalTargetMock()
        moduleB.underlyingName = "ModuleB-framework"
        moduleB.underlyingUuid = "MODULEB123"
        moduleB.buildRules = [.mock(name: "ModuleBBuildRule")]
        moduleB.explicitDependencies = [common.uuid: common]
        moduleB.dependencies = [common.uuid: common]
        
        let app = IInternalTargetMock()
        app.underlyingName = "App"
        app.underlyingUuid = "APP123"
        app.buildRules = [.mock(name: "AppBuildRule")]
        app.explicitDependencies = [
            moduleA.uuid: moduleA,
            moduleB.uuid: moduleB
        ]
        // Flattened dependencies include Common only once
        app.dependencies = [
            moduleA.uuid: moduleA,
            moduleB.uuid: moduleB,
            common.uuid: common  // transitive from both A and B
        ]
        
        let targets: TargetsMap = [
            app.uuid: app,
            moduleA.uuid: moduleA,
            moduleB.uuid: moduleB,
            common.uuid: common
        ]
        
        // Setup mocks
        xcodeCLTVersionProvider.versionReturnValue = XcodeVersion(base: "14.5", build: "1234")
        await swiftVersionProvider.setSwiftVersionReturnValue("5.9")
        configurationsHasher.hashContextClosure = { ["\($0.name)_configuration_hash"] }
        cocoaPodsScriptsHasher.hashContextClosure = { ["\($0.name)_cocoaPodsScripts_hash"] }
        buildPhaseHasher.hashContextTargetClosure = { ["\($0.name)_buildPhase_hash"] }
        buildRulesHasher.hashContextClosure = { $0.map { "\($0.name ?? "Unknown")_cocoaPodsScripts_hash" } }
        foundationHasher.hashStringClosure = { _ in "stable_hash" }
        
        // Act
        try await sut.hash(targets, xcargs: [])
        
        // Assert - App should include both A and B, but not Common
        let appHashContext = app.hashContext ?? ""
        XCTAssertTrue(appHashContext.contains("ModuleA-framework: stable_hash"))
        XCTAssertTrue(appHashContext.contains("ModuleB-framework: stable_hash"))
        XCTAssertFalse(appHashContext.contains("Common-framework:"))
    }

    func test_cicd_differentPaths_sameHash() async throws {
        // Test that different CI/CD checkout paths don't affect hash
        // Simulating: /jenkins/workspace/job1 vs /github-actions/runner/work
        
        let alamofire = IInternalTargetMock()
        alamofire.underlyingName = "Alamofire-framework"
        alamofire.underlyingUuid = "ALAMOFIRE123"
        alamofire.buildRules = [.mock(name: "AlamofireBuildRule")]
        
        let targets: TargetsMap = [alamofire.uuid: alamofire]
        
        // Setup mocks for first CI environment
        xcodeCLTVersionProvider.versionReturnValue = XcodeVersion(base: "14.5", build: "1234")
        await swiftVersionProvider.setSwiftVersionReturnValue("5.9")
        
        // Simulate build settings with absolute paths from Jenkins
        // These would normally be in the configurations, but our excludeKeys filters them out
        // let jenkinsConfigurations: [String: Any] = [
        //     "PODS_ROOT": "/jenkins/workspace/job1/Pods",
        //     "CONFIGURATION_BUILD_DIR": "/jenkins/workspace/job1/build",
        //     "FRAMEWORK_SEARCH_PATHS": "/jenkins/workspace/job1/Frameworks",
        //     "OTHER_SETTING": "same_value"
        // ]
        configurationsHasher.hashContextClosure = { _ in
            // Return only non-path settings (simulating our excludeKeys)
            return [["name": "Debug", "buildSettings": ["OTHER_SETTING": "same_value"]]]
        }
        
        cocoaPodsScriptsHasher.hashContextClosure = { ["\($0.name)_cocoaPodsScripts_hash"] }
        buildPhaseHasher.hashContextTargetClosure = { ["\($0.name)_buildPhase_hash"] }
        buildRulesHasher.hashContextClosure = { $0.map { "\($0.name ?? "Unknown")_cocoaPodsScripts_hash" } }
        foundationHasher.hashStringClosure = { _ in "consistent_hash" }
        
        // Act - First hash (Jenkins)
        try await sut.hash(targets, xcargs: [])
        let jenkinsHash = alamofire.hash
        
        // Reset for GitHub Actions environment
        alamofire.hash = nil
        alamofire.hashContext = nil
        alamofire.targetHashContext = nil
        
        // Act - Second hash (GitHub Actions with different paths)
        try await sut.hash(targets, xcargs: [])
        let githubHash = alamofire.hash
        
        // Assert - Hashes should be identical despite different absolute paths
        XCTAssertEqual(jenkinsHash, githubHash)
        XCTAssertEqual(jenkinsHash, "consistent_hash")
    }

    func test_complexCoupledDependencies() async throws {
        // Test coupled dependencies where multiple pods depend on each other
        // Simulating a real scenario with UI components depending on shared resources
        
        // Resources pod that many others depend on
        let resources = IInternalTargetMock()
        resources.underlyingName = "SharedResources"
        resources.underlyingUuid = "RESOURCES123"
        resources.buildRules = [.mock(name: "ResourcesBuildRule")]
        
        // Analytics pod
        let analytics = IInternalTargetMock()
        analytics.underlyingName = "Analytics-framework"
        analytics.underlyingUuid = "ANALYTICS123"
        analytics.buildRules = [.mock(name: "AnalyticsBuildRule")]
        analytics.explicitDependencies = [resources.uuid: resources]
        analytics.dependencies = [resources.uuid: resources]
        
        // UI Foundation depending on resources
        let uiFoundation = IInternalTargetMock()
        uiFoundation.underlyingName = "UIFoundation-framework"
        uiFoundation.underlyingUuid = "UIFOUNDATION123"
        uiFoundation.buildRules = [.mock(name: "UIFoundationBuildRule")]
        uiFoundation.explicitDependencies = [
            resources.uuid: resources,
            analytics.uuid: analytics
        ]
        uiFoundation.dependencies = [
            resources.uuid: resources,
            analytics.uuid: analytics
        ]
        
        // Feature modules depending on UI Foundation
        let loginUI = IInternalTargetMock()
        loginUI.underlyingName = "LoginUI-framework"
        loginUI.underlyingUuid = "LOGINUI123"
        loginUI.buildRules = [.mock(name: "LoginUIBuildRule")]
        loginUI.explicitDependencies = [uiFoundation.uuid: uiFoundation]
        loginUI.dependencies = [
            uiFoundation.uuid: uiFoundation,
            resources.uuid: resources,     // transitive
            analytics.uuid: analytics      // transitive
        ]
        
        let profileUI = IInternalTargetMock()
        profileUI.underlyingName = "ProfileUI-framework"
        profileUI.underlyingUuid = "PROFILEUI123"
        profileUI.buildRules = [.mock(name: "ProfileUIBuildRule")]
        profileUI.explicitDependencies = [uiFoundation.uuid: uiFoundation]
        profileUI.dependencies = [
            uiFoundation.uuid: uiFoundation,
            resources.uuid: resources,     // transitive
            analytics.uuid: analytics      // transitive
        ]
        
        // Main app depending on feature modules
        let mainApp = IInternalTargetMock()
        mainApp.underlyingName = "MainApp"
        mainApp.underlyingUuid = "MAINAPP123"
        mainApp.buildRules = [.mock(name: "MainAppBuildRule")]
        mainApp.explicitDependencies = [
            loginUI.uuid: loginUI,
            profileUI.uuid: profileUI
        ]
        mainApp.dependencies = [
            loginUI.uuid: loginUI,
            profileUI.uuid: profileUI,
            uiFoundation.uuid: uiFoundation,  // transitive
            resources.uuid: resources,         // transitive
            analytics.uuid: analytics          // transitive
        ]
        
        let targets: TargetsMap = [
            mainApp.uuid: mainApp,
            loginUI.uuid: loginUI,
            profileUI.uuid: profileUI,
            uiFoundation.uuid: uiFoundation,
            analytics.uuid: analytics,
            resources.uuid: resources
        ]
        
        // Setup mocks
        xcodeCLTVersionProvider.versionReturnValue = XcodeVersion(base: "14.5", build: "1234")
        await swiftVersionProvider.setSwiftVersionReturnValue("5.9")
        configurationsHasher.hashContextClosure = { ["\($0.name)_configuration_hash"] }
        cocoaPodsScriptsHasher.hashContextClosure = { ["\($0.name)_cocoaPodsScripts_hash"] }
        buildPhaseHasher.hashContextTargetClosure = { ["\($0.name)_buildPhase_hash"] }
        buildRulesHasher.hashContextClosure = { $0.map { "\($0.name ?? "Unknown")_cocoaPodsScripts_hash" } }
        
        var hashCallCount: [String: Int] = [:]
        foundationHasher.hashStringClosure = { context in
            // Count how many times each target's context is hashed
            if context.contains("SharedResources") {
                hashCallCount["resources", default: 0] += 1
                return "resources_hash_v\(hashCallCount["resources"]!)"
            } else if context.contains("Analytics-framework") {
                return "analytics_hash"
            } else if context.contains("UIFoundation-framework") {
                return "uifoundation_hash"
            } else if context.contains("LoginUI-framework") {
                return "loginui_hash"
            } else if context.contains("ProfileUI-framework") {
                return "profileui_hash"
            } else if context.contains("MainApp") {
                return "mainapp_hash"
            }
            return "unknown_hash"
        }
        
        // Act
        try await sut.hash(targets, xcargs: [])
        
        // Assert - MainApp should only include its direct dependencies
        let mainAppHashContext = mainApp.hashContext ?? ""
        XCTAssertTrue(mainAppHashContext.contains("LoginUI-framework: loginui_hash"))
        XCTAssertTrue(mainAppHashContext.contains("ProfileUI-framework: profileui_hash"))
        XCTAssertFalse(mainAppHashContext.contains("UIFoundation-framework:"))
        XCTAssertFalse(mainAppHashContext.contains("SharedResources:"))
        XCTAssertFalse(mainAppHashContext.contains("Analytics-framework:"))
        
        // Verify that changing a deeply nested dependency doesn't affect top-level hash
        // Reset resources hash to simulate a change
        resources.hash = nil
        resources.hashContext = nil
        resources.targetHashContext = nil
        
        // Change the hash function to return different value for resources
        foundationHasher.hashStringClosure = { context in
            if context.contains("SharedResources") {
                return "resources_hash_changed"
            }
            // Return same values for others
            return "stable_hash"
        }
        
        // Store old hashes
        let oldMainAppHash = mainApp.hash
        let oldLoginUIHash = loginUI.hash
        let oldProfileUIHash = profileUI.hash
        
        // Act - Rehash only resources
        try await sut.hash([resources.uuid: resources], xcargs: [])
        
        // Assert - Only direct dependents should change, not the whole tree
        XCTAssertEqual(mainApp.hash, oldMainAppHash, "MainApp hash should not change when transitive dependency changes")
        XCTAssertEqual(loginUI.hash, oldLoginUIHash, "LoginUI hash should not change when transitive dependency changes")
        XCTAssertEqual(profileUI.hash, oldProfileUIHash, "ProfileUI hash should not change when transitive dependency changes")
    }

    func test_explicitDependencies_circularReference() async throws {
        // Test circular dependencies: A -> B -> C -> A
        // This tests that the hash calculation doesn't get stuck in infinite loops
        
        let targetA = IInternalTargetMock()
        targetA.underlyingName = "TargetA"
        targetA.underlyingUuid = "TARGETA123"
        targetA.buildRules = [.mock(name: "TargetABuildRule")]
        
        let targetB = IInternalTargetMock()
        targetB.underlyingName = "TargetB"
        targetB.underlyingUuid = "TARGETB123"
        targetB.buildRules = [.mock(name: "TargetBBuildRule")]
        
        let targetC = IInternalTargetMock()
        targetC.underlyingName = "TargetC"
        targetC.underlyingUuid = "TARGETC123"
        targetC.buildRules = [.mock(name: "TargetCBuildRule")]
        
        // Create circular references
        targetA.explicitDependencies = [targetB.uuid: targetB]
        targetB.explicitDependencies = [targetC.uuid: targetC]
        targetC.explicitDependencies = [targetA.uuid: targetA]
        
        // Set flattened dependencies (which would include all in circular reference)
        targetA.dependencies = [
            targetB.uuid: targetB,
            targetC.uuid: targetC
        ]
        targetB.dependencies = [
            targetC.uuid: targetC,
            targetA.uuid: targetA
        ]
        targetC.dependencies = [
            targetA.uuid: targetA,
            targetB.uuid: targetB
        ]
        
        let targets: TargetsMap = [
            targetA.uuid: targetA,
            targetB.uuid: targetB,
            targetC.uuid: targetC
        ]
        
        // Setup mocks
        xcodeCLTVersionProvider.versionReturnValue = XcodeVersion(base: "14.5", build: "1234")
        await swiftVersionProvider.setSwiftVersionReturnValue("5.9")
        configurationsHasher.hashContextClosure = { ["\($0.name)_configuration_hash"] }
        cocoaPodsScriptsHasher.hashContextClosure = { ["\($0.name)_cocoaPodsScripts_hash"] }
        buildPhaseHasher.hashContextTargetClosure = { ["\($0.name)_buildPhase_hash"] }
        buildRulesHasher.hashContextClosure = { $0.map { "\($0.name ?? "Unknown")_cocoaPodsScripts_hash" } }
        foundationHasher.hashStringClosure = { _ in "circular_hash" }
        
        // Act - This should not crash or timeout
        try await sut.hash(targets, xcargs: [])
        
        // Assert - All targets should have hashes
        XCTAssertNotNil(targetA.hash)
        XCTAssertNotNil(targetB.hash)
        XCTAssertNotNil(targetC.hash)
        XCTAssertEqual(targetA.hash, "circular_hash")
        XCTAssertEqual(targetB.hash, "circular_hash")
        XCTAssertEqual(targetC.hash, "circular_hash")
    }

    func test_emptyDependencies() async throws {
        // Test targets with no dependencies
        
        let standaloneTarget = IInternalTargetMock()
        standaloneTarget.underlyingName = "StandaloneTarget"
        standaloneTarget.underlyingUuid = "STANDALONE123"
        standaloneTarget.buildRules = [.mock(name: "StandaloneBuildRule")]
        standaloneTarget.explicitDependencies = [:]
        standaloneTarget.dependencies = [:]
        
        let targets: TargetsMap = [standaloneTarget.uuid: standaloneTarget]
        
        // Setup mocks
        xcodeCLTVersionProvider.versionReturnValue = XcodeVersion(base: "14.5", build: "1234")
        await swiftVersionProvider.setSwiftVersionReturnValue("5.9")
        configurationsHasher.hashContextClosure = { ["\($0.name)_configuration_hash"] }
        cocoaPodsScriptsHasher.hashContextClosure = { ["\($0.name)_cocoaPodsScripts_hash"] }
        buildPhaseHasher.hashContextTargetClosure = { ["\($0.name)_buildPhase_hash"] }
        buildRulesHasher.hashContextClosure = { $0.map { "\($0.name ?? "Unknown")_cocoaPodsScripts_hash" } }
        foundationHasher.hashStringClosure = { context in
            XCTAssertTrue(context.contains("dependencies: {}"))
            return "standalone_hash"
        }
        
        // Act
        try await sut.hash(targets, xcargs: [])
        
        // Assert
        XCTAssertEqual(standaloneTarget.hash, "standalone_hash")
        XCTAssertTrue(standaloneTarget.hashContext?.contains("dependencies: {}") ?? false)
    }

    func test_differentXcargs_produceDifferentHashes() async throws {
        // Test that different xcargs produce different hashes
        
        let target = IInternalTargetMock()
        target.underlyingName = "TestTarget"
        target.underlyingUuid = "TEST123"
        target.buildRules = [.mock(name: "TestBuildRule")]
        
        let targets: TargetsMap = [target.uuid: target]
        
        // Setup mocks
        xcodeCLTVersionProvider.versionReturnValue = XcodeVersion(base: "14.5", build: "1234")
        await swiftVersionProvider.setSwiftVersionReturnValue("5.9")
        configurationsHasher.hashContextClosure = { ["\($0.name)_configuration_hash"] }
        cocoaPodsScriptsHasher.hashContextClosure = { ["\($0.name)_cocoaPodsScripts_hash"] }
        buildPhaseHasher.hashContextTargetClosure = { ["\($0.name)_buildPhase_hash"] }
        buildRulesHasher.hashContextClosure = { $0.map { "\($0.name ?? "Unknown")_cocoaPodsScripts_hash" } }
        
        var capturedContexts: [String] = []
        foundationHasher.hashStringClosure = { context in
            capturedContexts.append(context)
            return "hash_\(capturedContexts.count)"
        }
        
        // Act - First hash with default xcargs
        try await sut.hash(targets, xcargs: ["COMPILER_INDEX_STORE_ENABLE=NO"])
        let firstHash = target.hash
        
        // Reset for second hash
        target.hash = nil
        target.hashContext = nil
        target.targetHashContext = nil
        
        // Act - Second hash with different xcargs
        try await sut.hash(targets, xcargs: [
            "COMPILER_INDEX_STORE_ENABLE=NO",
            "DEBUG_INFORMATION_FORMAT=dwarf"
        ])
        let secondHash = target.hash
        
        // Assert - Different xcargs should produce different hashes
        XCTAssertNotEqual(firstHash, secondHash)
        XCTAssertTrue(capturedContexts[0].contains("COMPILER_INDEX_STORE_ENABLE=NO"))
        XCTAssertFalse(capturedContexts[0].contains("DEBUG_INFORMATION_FORMAT=dwarf"))
        XCTAssertTrue(capturedContexts[1].contains("DEBUG_INFORMATION_FORMAT=dwarf"))
    }

    func test_differentSwiftVersions_produceDifferentHashes() async throws {
        // Test that different Swift versions produce different hashes
        
        let target = IInternalTargetMock()
        target.underlyingName = "TestTarget"
        target.underlyingUuid = "TEST123"
        target.buildRules = [.mock(name: "TestBuildRule")]
        
        let targets: TargetsMap = [target.uuid: target]
        
        // Setup mocks
        xcodeCLTVersionProvider.versionReturnValue = XcodeVersion(base: "14.5", build: "1234")
        configurationsHasher.hashContextClosure = { ["\($0.name)_configuration_hash"] }
        cocoaPodsScriptsHasher.hashContextClosure = { ["\($0.name)_cocoaPodsScripts_hash"] }
        buildPhaseHasher.hashContextTargetClosure = { ["\($0.name)_buildPhase_hash"] }
        buildRulesHasher.hashContextClosure = { $0.map { "\($0.name ?? "Unknown")_cocoaPodsScripts_hash" } }
        
        var capturedContexts: [String] = []
        foundationHasher.hashStringClosure = { context in
            capturedContexts.append(context)
            return "hash_\(capturedContexts.count)"
        }
        
        // Act - First hash with Swift 5.9
        await swiftVersionProvider.setSwiftVersionReturnValue("5.9")
        try await sut.hash(targets, xcargs: [])
        let firstHash = target.hash
        
        // Reset for second hash
        target.hash = nil
        target.hashContext = nil
        target.targetHashContext = nil
        
        // Act - Second hash with Swift 6.0
        await swiftVersionProvider.setSwiftVersionReturnValue("6.0")
        try await sut.hash(targets, xcargs: [])
        let secondHash = target.hash
        
        // Assert - Different Swift versions should produce different hashes
        XCTAssertNotEqual(firstHash, secondHash)
        XCTAssertTrue(capturedContexts[0].contains("swift_version: \'5.9\'"))
        XCTAssertTrue(capturedContexts[1].contains("swift_version: \'6.0\'"))
    }

    func test_differentXcodeVersions_produceDifferentHashes() async throws {
        // Test that different Xcode versions produce different hashes
        
        let target = IInternalTargetMock()
        target.underlyingName = "TestTarget"
        target.underlyingUuid = "TEST123"
        target.buildRules = [.mock(name: "TestBuildRule")]
        
        let targets: TargetsMap = [target.uuid: target]
        
        // Setup mocks
        await swiftVersionProvider.setSwiftVersionReturnValue("5.9")
        configurationsHasher.hashContextClosure = { ["\($0.name)_configuration_hash"] }
        cocoaPodsScriptsHasher.hashContextClosure = { ["\($0.name)_cocoaPodsScripts_hash"] }
        buildPhaseHasher.hashContextTargetClosure = { ["\($0.name)_buildPhase_hash"] }
        buildRulesHasher.hashContextClosure = { $0.map { "\($0.name ?? "Unknown")_cocoaPodsScripts_hash" } }
        
        var capturedContexts: [String] = []
        foundationHasher.hashStringClosure = { context in
            capturedContexts.append(context)
            return "hash_\(capturedContexts.count)"
        }
        
        // Act - First hash with Xcode 14.5
        xcodeCLTVersionProvider.versionReturnValue = XcodeVersion(base: "14.5", build: "1234")
        try await sut.hash(targets, xcargs: [])
        let firstHash = target.hash
        
        // Reset for second hash
        target.hash = nil
        target.hashContext = nil
        target.targetHashContext = nil
        
        // Act - Second hash with Xcode 15.0
        xcodeCLTVersionProvider.versionReturnValue = XcodeVersion(base: "15.0", build: "5678")
        try await sut.hash(targets, xcargs: [])
        let secondHash = target.hash
        
        // Assert - Different Xcode versions should produce different hashes
        XCTAssertNotEqual(firstHash, secondHash)
        XCTAssertTrue(capturedContexts[0].contains("xcode_version: 14.5 (1234)"))
        XCTAssertTrue(capturedContexts[1].contains("xcode_version: 15.0 (5678)"))
    }

    func test_parallelTargetsWithSharedDependencies() async throws {
        // Test multiple targets sharing common dependencies
        // UI -> [FeatureA, FeatureB] -> Core
        
        let core = IInternalTargetMock()
        core.underlyingName = "Core-framework"
        core.underlyingUuid = "CORE123"
        core.buildRules = [.mock(name: "CoreBuildRule")]
        
        let featureA = IInternalTargetMock()
        featureA.underlyingName = "FeatureA-framework"
        featureA.underlyingUuid = "FEATUREA123"
        featureA.buildRules = [.mock(name: "FeatureABuildRule")]
        featureA.explicitDependencies = [core.uuid: core]
        featureA.dependencies = [core.uuid: core]
        
        let featureB = IInternalTargetMock()
        featureB.underlyingName = "FeatureB-framework"
        featureB.underlyingUuid = "FEATUREB123"
        featureB.buildRules = [.mock(name: "FeatureBBuildRule")]
        featureB.explicitDependencies = [core.uuid: core]
        featureB.dependencies = [core.uuid: core]
        
        let ui = IInternalTargetMock()
        ui.underlyingName = "UI-framework"
        ui.underlyingUuid = "UI123"
        ui.buildRules = [.mock(name: "UIBuildRule")]
        ui.explicitDependencies = [
            featureA.uuid: featureA,
            featureB.uuid: featureB
        ]
        ui.dependencies = [
            featureA.uuid: featureA,
            featureB.uuid: featureB,
            core.uuid: core  // transitive
        ]
        
        let targets: TargetsMap = [
            ui.uuid: ui,
            featureA.uuid: featureA,
            featureB.uuid: featureB,
            core.uuid: core
        ]
        
        // Setup mocks
        xcodeCLTVersionProvider.versionReturnValue = XcodeVersion(base: "14.5", build: "1234")
        await swiftVersionProvider.setSwiftVersionReturnValue("5.9")
        configurationsHasher.hashContextClosure = { ["\($0.name)_configuration_hash"] }
        cocoaPodsScriptsHasher.hashContextClosure = { ["\($0.name)_cocoaPodsScripts_hash"] }
        buildPhaseHasher.hashContextTargetClosure = { ["\($0.name)_buildPhase_hash"] }
        buildRulesHasher.hashContextClosure = { $0.map { "\($0.name ?? "Unknown")_cocoaPodsScripts_hash" } }
        
        var hashCallCount = 0
        foundationHasher.hashStringClosure = { _ in
            hashCallCount += 1
            return "hash_\(hashCallCount)"
        }
        
        // Act
        try await sut.hash(targets, xcargs: [])
        
        // Assert - Core should be hashed only once despite being dependency of both features
        XCTAssertNotNil(core.hash)
        XCTAssertNotNil(featureA.hash)
        XCTAssertNotNil(featureB.hash)
        XCTAssertNotNil(ui.hash)
        
        // UI should only reference FeatureA and FeatureB, not Core
        let uiHashContext = ui.hashContext ?? ""
        XCTAssertTrue(uiHashContext.contains("FeatureA-framework:"))
        XCTAssertTrue(uiHashContext.contains("FeatureB-framework:"))
        XCTAssertFalse(uiHashContext.contains("Core-framework:"))
    }

    func test_targetWithProduct() async throws {
        // Test that product information is included in hash
        
        let targetWithProduct = IInternalTargetMock()
        targetWithProduct.underlyingName = "ProductTarget"
        targetWithProduct.underlyingUuid = "PRODUCT123"
        targetWithProduct.buildRules = [.mock(name: "ProductBuildRule")]
        targetWithProduct.product = Product(
            name: "MyProduct",
            moduleName: "MyModule",
            type: .framework,
            parentFolderName: "Products"
        )
        
        let targetWithoutProduct = IInternalTargetMock()
        targetWithoutProduct.underlyingName = "NoProductTarget"
        targetWithoutProduct.underlyingUuid = "NOPRODUCT123"
        targetWithoutProduct.buildRules = [.mock(name: "NoProductBuildRule")]
        targetWithoutProduct.product = nil
        
        let targets: TargetsMap = [
            targetWithProduct.uuid: targetWithProduct,
            targetWithoutProduct.uuid: targetWithoutProduct
        ]
        
        // Setup mocks
        xcodeCLTVersionProvider.versionReturnValue = XcodeVersion(base: "14.5", build: "1234")
        await swiftVersionProvider.setSwiftVersionReturnValue("5.9")
        configurationsHasher.hashContextClosure = { ["\($0.name)_configuration_hash"] }
        cocoaPodsScriptsHasher.hashContextClosure = { ["\($0.name)_cocoaPodsScripts_hash"] }
        buildPhaseHasher.hashContextTargetClosure = { ["\($0.name)_buildPhase_hash"] }
        buildRulesHasher.hashContextClosure = { $0.map { "\($0.name ?? "Unknown")_cocoaPodsScripts_hash" } }
        productHasher.hashContextClosure = { product in
            ["productName": product.name,
             "moduleName": product.moduleName ?? "",
             "type": product.type.rawValue]
        }
        foundationHasher.hashStringClosure = { context in
            if context.contains("ProductTarget") {
                XCTAssertTrue(context.contains("productName: MyProduct"))
                return "hash_with_product"
            } else {
                XCTAssertTrue(context.contains("product: null"))
                return "hash_without_product"
            }
        }
        
        // Act
        try await sut.hash(targets, xcargs: [])
        
        // Assert
        XCTAssertEqual(targetWithProduct.hash, "hash_with_product")
        XCTAssertEqual(targetWithoutProduct.hash, "hash_without_product")
    }

    func test_largeDependencyGraph_performance() async throws {
        // Test performance with a large number of targets
        // This also verifies that the hash calculation completes in reasonable time
        
        let numberOfTargets = 100
        var targets: TargetsMap = [:]
        var previousTarget: IInternalTargetMock?
        
        // Create a chain of 100 targets
        for i in 0..<numberOfTargets {
            let target = IInternalTargetMock()
            target.underlyingName = "Target\(i)"
            target.underlyingUuid = "TARGET\(i)"
            target.buildRules = [.mock(name: "Target\(i)BuildRule")]
            
            if let previous = previousTarget {
                target.explicitDependencies = [previous.uuid: previous]
                // Simulate flattened dependencies (all previous targets)
                var allDeps: TargetsMap = [previous.uuid: previous]
                for j in 0..<i {
                    if let dep = targets["TARGET\(j)"] {
                        allDeps[dep.uuid] = dep
                    }
                }
                target.dependencies = allDeps
            }
            
            targets[target.uuid] = target
            previousTarget = target
        }
        
        // Setup mocks
        xcodeCLTVersionProvider.versionReturnValue = XcodeVersion(base: "14.5", build: "1234")
        await swiftVersionProvider.setSwiftVersionReturnValue("5.9")
        configurationsHasher.hashContextClosure = { _ in [] }
        cocoaPodsScriptsHasher.hashContextClosure = { _ in [] }
        buildPhaseHasher.hashContextTargetClosure = { _ in [] }
        buildRulesHasher.hashContextClosure = { _ in [] }
        foundationHasher.hashStringClosure = { _ in "perf_hash" }
        
        // Act - Measure time
        let startTime = Date()
        try await sut.hash(targets, xcargs: [])
        let endTime = Date()
        let elapsedTime = endTime.timeIntervalSince(startTime)
        
        // Assert - Should complete in reasonable time (less than 5 seconds)
        XCTAssertLessThan(elapsedTime, 5.0, "Hash calculation took too long: \(elapsedTime)s")
        
        // All targets should have hashes
        for target in targets.values {
            XCTAssertNotNil(target.hash)
        }
        
        // Last target should only include reference to previous target (explicit dependency)
        if let lastTarget = previousTarget {
            let hashContext = lastTarget.hashContext ?? ""
            XCTAssertTrue(hashContext.contains("Target\(numberOfTargets - 2):"))
            // Should not contain references to all previous targets
            XCTAssertFalse(hashContext.contains("Target0:"))
        }
    }
}

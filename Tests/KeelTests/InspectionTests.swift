import Foundation
import Testing
@testable import KeelKit

/// Inspection is tested against projects Keel itself generates.
///
/// That keeps the fixtures honest — they are real Xcode projects that build,
/// not hand-written pbxproj snippets that drift from the format Xcode
/// actually writes.
@Suite("ProjectScanner")
struct ProjectScannerTests {

    private let console = Console(useColor: false)

    private func withGeneratedProject<T>(
        name: String = "Probe",
        components: Set<Component> = Set(Component.allCases),
        _ body: (URL) throws -> T
    ) throws -> T {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-inspect-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let configuration = ProjectConfiguration(
            name: try ProjectName(name),
            bundleIdentifierPrefix: "com.acme",
            components: components
        )
        let outcome = try ProjectGenerator(configuration: configuration, console: console)
            .generate(in: destination, initializeGit: false)
        return try body(outcome.projectDirectory)
    }

    // MARK: - Structure

    @Test("Finds the project and reads its name")
    func findsProject() throws {
        try withGeneratedProject { root in
            let inspection = try ProjectScanner(root: root).scan()
            #expect(inspection.name == "Probe")
            #expect(inspection.projects.count == 1)
            #expect(inspection.projects.first?.objectVersion == 77)
        }
    }

    @Test("Reads app and test targets with their product types")
    func readsTargets() throws {
        try withGeneratedProject { root in
            let inspection = try ProjectScanner(root: root).scan()

            #expect(inspection.allTargets.count == 2)
            #expect(inspection.appTargets.map(\.name) == ["Probe"])
            #expect(inspection.testTargets.map(\.name) == ["ProbeTests"])
            #expect(inspection.testTargets.first?.productType == .unitTestBundle)
        }
    }

    @Test("Reads build settings, including ones inherited from the project")
    func readsBuildSettings() throws {
        try withGeneratedProject { root in
            let inspection = try ProjectScanner(root: root).scan()
            let app = try #require(inspection.appTargets.first)

            #expect(app.bundleIdentifier == "com.acme.probe")
            #expect(app.swiftVersion == "6.0")
            #expect(app.strictConcurrency == "complete")
            // Declared once at project level and inherited by both targets.
            #expect(inspection.minimumDeploymentTarget == "17.0")
        }
    }

    @Test("A project without a test target reports none")
    func reportsNoTestTarget() throws {
        var components = Set(Component.allCases)
        components.remove(.testing)

        try withGeneratedProject(name: "Plain", components: components) { root in
            let inspection = try ProjectScanner(root: root).scan()
            #expect(inspection.testTargets.isEmpty)
            #expect(inspection.allTargets.count == 1)
        }
    }

    // MARK: - Schemes

    @Test("A scheme in xcshareddata is reported as shared")
    func detectsSharedScheme() throws {
        try withGeneratedProject { root in
            let inspection = try ProjectScanner(root: root).scan()
            #expect(inspection.schemes.map(\.name) == ["Probe"])
            // Shared is what lets CI and a fresh clone build the project.
            #expect(inspection.schemes.first?.isShared == true)
        }
    }

    @Test("A scheme only under xcuserdata is reported as not shared")
    func detectsUnsharedScheme() throws {
        try withGeneratedProject { root in
            let userSchemes = root
                .appendingPathComponent("Probe.xcodeproj/xcuserdata/someone.xcuserdatad/xcschemes")
            try FileManager.default.createDirectory(at: userSchemes, withIntermediateDirectories: true)
            try Data("<Scheme/>".utf8)
                .write(to: userSchemes.appendingPathComponent("Local.xcscheme"))

            let inspection = try ProjectScanner(root: root).scan()
            let local = try #require(inspection.schemes.first { $0.name == "Local" })
            #expect(local.isShared == false)
        }
    }

    // MARK: - Source

    @Test("Summarises the source without parsing it")
    func summarisesSource() throws {
        try withGeneratedProject { root in
            let source = try ProjectScanner(root: root).scan().source

            #expect(source.swiftFileCount > 0)
            #expect(source.lineCount > 0)
            #expect(source.importsSwiftUI)
            #expect(source.uiFramework == "SwiftUI")
            #expect(source.usesObservationMacro)
            #expect(source.usesAsyncAwait)
            #expect(source.usesSwiftTesting)
            #expect(source.usesSwiftData)
            // Keel generates no ObservableObject or Combine, so a false
            // positive here would mean the markers are matching too loosely.
            #expect(source.usesObservableObject == false)
            #expect(source.usesCombine == false)
        }
    }

    @Test("Vendored directories are skipped, not counted")
    func skipsVendoredDirectories() throws {
        try withGeneratedProject { root in
            let before = try ProjectScanner(root: root).scan().source.swiftFileCount

            // Pods and DerivedData can hold far more source than the project,
            // and would dominate every count.
            let pods = root.appendingPathComponent("Pods/SomeDependency")
            try FileManager.default.createDirectory(at: pods, withIntermediateDirectories: true)
            for index in 1...5 {
                try Data("import UIKit\nclass Thing\(index) {}\n".utf8)
                    .write(to: pods.appendingPathComponent("Thing\(index).swift"))
            }

            let after = try ProjectScanner(root: root).scan().source
            #expect(after.swiftFileCount == before)
            #expect(after.importsUIKit == false)
        }
    }

    // MARK: - Failure

    @Test("A directory with no project reports that clearly")
    func reportsMissingProject() throws {
        let empty = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }

        #expect(throws: ProjectScanner.ScanError.self) {
            try ProjectScanner(root: empty).scan()
        }
    }

    // MARK: - Serialization

    @Test("The inspection round-trips through Codable, for --json")
    func inspectionIsCodable() throws {
        try withGeneratedProject { root in
            let inspection = try ProjectScanner(root: root).scan()
            let data = try JSONEncoder().encode(inspection)
            let decoded = try JSONDecoder().decode(ProjectModel.self, from: data)
            #expect(decoded == inspection)
        }
    }
}

// MARK: - pbxproj details

@Suite("PBXProjectFile")
struct PBXProjectFileTests {

    @Test("Derives a package name from its repository URL")
    func derivesPackageName() {
        #expect(
            PBXProjectFile.packageName(fromRepositoryURL: "https://github.com/apple/swift-argument-parser.git")
                == "swift-argument-parser"
        )
        #expect(
            PBXProjectFile.packageName(fromRepositoryURL: "https://github.com/GRimAce11/MarqueeKit")
                == "MarqueeKit"
        )
    }

    @Test("Renders each package requirement the way Xcode states it")
    func describesRequirements() {
        #expect(
            PBXProjectFile.describe(requirement: ["kind": "upToNextMajorVersion", "minimumVersion": "1.2.0"])
                == "from 1.2.0"
        )
        #expect(
            PBXProjectFile.describe(requirement: ["kind": "exactVersion", "version": "3.0.0"])
                == "exactly 3.0.0"
        )
        #expect(
            PBXProjectFile.describe(requirement: ["kind": "branch", "branch": "main"])
                == "branch main"
        )
        #expect(PBXProjectFile.describe(requirement: nil) == nil)
    }

    @Test("An unreadable project file is reported, not crashed on")
    func reportsMalformedProject() throws {
        let fake = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Broken-\(UUID().uuidString).xcodeproj")
        try FileManager.default.createDirectory(at: fake, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fake) }
        try Data("this is not a property list {{{".utf8)
            .write(to: fake.appendingPathComponent("project.pbxproj"))

        #expect(throws: PBXProjectFile.ParseError.self) {
            try PBXProjectFile(path: fake)
        }
    }
}

// MARK: - Versions

@Suite("VersionNumber")
struct VersionNumberTests {

    @Test("Compares numerically rather than as text")
    func comparesNumerically() {
        // Sorted as strings, "9.0" comes after "17.0" — which would report the
        // wrong minimum deployment target for anything still supporting iOS 9.
        #expect(VersionNumber("9.0") < VersionNumber("17.0"))
        #expect(VersionNumber("17.0") < VersionNumber("17.4"))
        #expect(VersionNumber("6") < VersionNumber("6.1"))
    }

    @Test("Treats a missing component as zero")
    func padsMissingComponents() {
        #expect(!(VersionNumber("18") < VersionNumber("18.0")))
        #expect(!(VersionNumber("18.0") < VersionNumber("18")))
    }
}

// MARK: - Monorepos

/// A project that shares a repository with other stacks.
///
/// The failure this guards against is quiet: Keel invoked at a monorepo root
/// used to scan every Swift file under it, so a Vapor backend's types were
/// counted as the app's and fed to architecture detection. Nothing errored —
/// the numbers were simply wrong, which is the worst way for an analysis tool
/// to fail.
@Suite("Monorepo scoping")
struct MonorepoTests {

    private let console = Console(useColor: false)

    /// `root/ios/<project>` alongside a Swift backend and other stacks.
    private func withMonorepo<T>(_ body: (URL, URL) throws -> T) throws -> T {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-mono-\(UUID().uuidString)")
        let staging = root.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let configuration = ProjectConfiguration(
            name: try ProjectName("Storefront"),
            bundleIdentifierPrefix: "com.acme",
            components: Set(Component.allCases)
        )
        let outcome = try ProjectGenerator(configuration: configuration, console: console)
            .generate(in: staging, initializeGit: false)

        // The shape a real monorepo uses: ios/Storefront.xcodeproj, with the
        // folder named for the stack rather than the product.
        let ios = root.appendingPathComponent("ios")
        try FileManager.default.moveItem(at: outcome.projectDirectory, to: ios)
        try FileManager.default.removeItem(at: staging)

        // A Swift backend, which is the case that actually breaks things.
        let backend = root.appendingPathComponent("backend/Sources/Server")
        try FileManager.default.createDirectory(at: backend, withIntermediateDirectories: true)
        for index in 1...6 {
            try """
                import Foundation

                final class ServerViewModel\(index) {
                    func handle() async throws {}
                }
                struct ServerRepository\(index) {}
                """.write(
                    to: backend.appendingPathComponent("Handler\(index).swift"),
                    atomically: true, encoding: .utf8
                )
        }

        return try body(root, ios)
    }

    @Test("Scanning a monorepo root sees only the iOS project")
    func scopesToTheProject() throws {
        try withMonorepo { root, ios in
            let fromRoot = try ProjectScanner(root: root).scan()
            let fromProject = try ProjectScanner(root: ios).scan()

            // The project file's own location is what says where the app ends.
            #expect(fromRoot.source.swiftFileCount == fromProject.source.swiftFileCount)
            #expect(fromRoot.source.lineCount == fromProject.source.lineCount)
            #expect(fromRoot.modules.map(\.name) == fromProject.modules.map(\.name))
        }
    }

    @Test("A Swift backend never reaches the app's analysis")
    func excludesOtherStacks() throws {
        try withMonorepo { root, _ in
            let model = try ProjectScanner(root: root).scan()
            let names = model.analysis.declaredTypes.map(\.name)

            #expect(!names.contains { $0.hasPrefix("ServerViewModel") })
            #expect(!names.contains { $0.hasPrefix("ServerRepository") })
        }
    }

    @Test("The name comes from the project file, not the folder it sits in")
    func namesFromTheProjectFile() throws {
        try withMonorepo { root, _ in
            // The directory is called `ios`; the project is not.
            let model = try ProjectScanner(root: root).scan()
            #expect(model.name == "Storefront")
        }
    }

    @Test("Paths are reported relative to the project, not the repository")
    func reportsProjectRelativePaths() throws {
        try withMonorepo { root, ios in
            let model = try ProjectScanner(root: root).scan()

            #expect(model.rootPath == ios.standardizedFileURL.path)
            #expect(model.analysis.files.allSatisfy { !$0.path.hasPrefix("ios/") })
        }
    }
}

// MARK: - Broken project files

@Suite("Unreadable projects")
struct UnreadableProjectTests {

    private let console = Console(useColor: false)

    @Test("A broken .xcodeproj beside a real one does not stop the real one being read")
    func skipsUnreadableProjects() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-broken-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let outcome = try ProjectGenerator(
            configuration: ProjectConfiguration(
                name: try ProjectName("Probe"),
                bundleIdentifierPrefix: "com.acme",
                components: []
            ),
            console: console
        ).generate(in: root, initializeGit: false)

        // A leftover: the directory exists, the project file inside does not.
        try FileManager.default.createDirectory(
            at: outcome.projectDirectory.appendingPathComponent("Leftover.xcodeproj"),
            withIntermediateDirectories: true
        )

        // A tool whose promise is working on broken projects cannot fall over
        // at the first broken thing it finds.
        let model = try ProjectScanner(root: outcome.projectDirectory).scan()
        #expect(model.name == "Probe")
        #expect(model.projects.map(\.name) == ["Probe"])
    }

    @Test("When nothing can be read, the reason says what is actually wrong")
    func explainsWhenNothingIsReadable() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-ghost-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Ghost.xcodeproj"), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            _ = try ProjectScanner(root: root).scan()
            Issue.record("expected a scan failure")
        } catch let error as ProjectScanner.ScanError {
            // "Could not read it" is not a diagnosis. Naming the missing file is.
            #expect(error.description.contains("project.pbxproj"))
            #expect(error.description.contains("Ghost.xcodeproj"))
        }
    }
}

// MARK: - Which target's folder is the source

@Suite("Source target selection")
struct SourceTargetTests {

    private func target(_ name: String, _ type: ProductType) -> Target {
        Target(
            name: name, productType: type, bundleIdentifier: nil,
            deploymentTarget: nil, swiftVersion: nil, platform: nil,
            strictConcurrency: nil
        )
    }

    @Test("Test bundles are never candidates for the app's source directory")
    func excludesTestBundles() {
        // A test target's folder holds tests. Treating it as the app's source
        // sends generated features into the test target.
        let names = ProjectModel.sourceTargetNames(from: [
            target("ProbeTests", .unitTestBundle),
            target("Probe", .application),
            target("ProbeUITests", .uiTestBundle),
        ])

        #expect(names == ["Probe"])
    }

    @Test("The app target comes first, whatever order Xcode wrote them in")
    func prefersTheAppTarget() {
        // Whoever looks for the source directory takes the first name that
        // matches, so this order is the answer rather than a nicety.
        let names = ProjectModel.sourceTargetNames(from: [
            target("ProbeWidgets", .appExtension),
            target("Probe", .application),
        ])

        #expect(names.first == "Probe")
    }

    @Test("A project with no app target still offers its other targets")
    func keepsNonAppTargets() {
        let names = ProjectModel.sourceTargetNames(from: [
            target("ProbeKit", .framework),
            target("ProbeKitTests", .unitTestBundle),
        ])

        #expect(names == ["ProbeKit"])
    }
}

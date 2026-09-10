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

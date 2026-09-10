import Foundation
import Testing
@testable import KeelKit

@Suite("TemplateCatalog")
struct TemplateCatalogTests {

    /// Builds a synthetic template tree so selection can be tested without
    /// depending on which templates happen to be written yet.
    private func makeTree(directories: [String]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keel-catalog-\(UUID().uuidString)")

        for directory in directories {
            let url = root.appendingPathComponent(directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("placeholder".utf8).write(to: url.appendingPathComponent("File.swift.tpl"))
        }
        return root
    }

    private func makeConfiguration(components: Set<Component>) throws -> ProjectConfiguration {
        ProjectConfiguration(name: try ProjectName("MyApp"), components: components)
    }

    // MARK: - Bundled templates

    @Test("The bundled template tree ships with the binary")
    func bundledTemplatesExist() throws {
        // Templates are compiled in rather than fetched, so generation works
        // offline and output is reproducible for a given Keel version.
        let catalog = try TemplateCatalog()
        let base = catalog.root.appendingPathComponent("Base")
        #expect(FileManager.default.fileExists(atPath: base.path))
    }

    @Test("Base is included whatever the configuration")
    func alwaysIncludesBase() throws {
        let catalog = try TemplateCatalog()
        let directories = catalog.directories(for: try makeConfiguration(components: []))

        #expect(directories.count == 1)
        #expect(directories.first?.lastPathComponent == "Base")
    }

    // MARK: - Selection

    @Test("Selects one directory per enabled component")
    func selectsEnabledComponents() throws {
        let root = try makeTree(directories: ["Base", "Networking", "Keychain", "DesignSystem"])
        let catalog = try TemplateCatalog(root: root)

        let directories = catalog.directories(
            for: try makeConfiguration(components: [.networking, .keychain])
        )
        let names = directories.map(\.lastPathComponent)

        #expect(names == ["Base", "Networking", "Keychain"])
        #expect(names.contains("DesignSystem") == false)
    }

    @Test("A component with no directory on disk is skipped, not an error")
    func toleratesMissingDirectory() throws {
        // A component that only toggles conditional blocks inside shared files
        // contributes no files of its own and needs no empty folder to say so.
        let root = try makeTree(directories: ["Base"])
        let catalog = try TemplateCatalog(root: root)

        let directories = catalog.directories(
            for: try makeConfiguration(components: [.networking, .persistence])
        )
        #expect(directories.map(\.lastPathComponent) == ["Base"])
    }

    @Test("Directory order follows the component declaration order, not Set order")
    func orderIsDeterministic() throws {
        // Set iteration order varies between runs; generation must not.
        let root = try makeTree(
            directories: ["Base", "Networking", "DependencyInjection", "Keychain", "Testing"]
        )
        let catalog = try TemplateCatalog(root: root)
        let components: Set<Component> = [.testing, .keychain, .networking, .dependencyInjection]

        let first = catalog.directories(for: try makeConfiguration(components: components))
        let second = catalog.directories(for: try makeConfiguration(components: components))

        #expect(first.map(\.lastPathComponent) == second.map(\.lastPathComponent))
        #expect(
            first.map(\.lastPathComponent)
                == ["Base", "Networking", "DependencyInjection", "Keychain", "Testing"]
        )
    }

    @Test("A file where a directory is expected is not selected")
    func ignoresNonDirectories() throws {
        let root = try makeTree(directories: ["Base"])
        try Data("not a directory".utf8)
            .write(to: root.appendingPathComponent("Networking"))

        let catalog = try TemplateCatalog(root: root)
        let directories = catalog.directories(
            for: try makeConfiguration(components: [.networking])
        )
        #expect(directories.map(\.lastPathComponent) == ["Base"])
    }

    // MARK: - Naming

    @Test("Every component maps to a distinct directory name")
    func directoryNamesAreUnique() {
        let names = Component.allCases.map(\.templateDirectoryName)
        #expect(Set(names).count == names.count)
        #expect(names.contains(TemplateCatalog.baseDirectoryName) == false)
    }
}

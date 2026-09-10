import Foundation
import Testing
@testable import KeelKit

@Suite("ProjectName")
struct ProjectNameTests {

    @Test("Keeps a name that is already valid")
    func passesThroughValidName() throws {
        let name = try ProjectName("MyApp")
        #expect(name.raw == "MyApp")
        #expect(name.slug == "my-app")
        #expect(name.wasSanitized == false)
    }

    @Test(
        "Normalises separators into upper camel case",
        arguments: [
            ("my cool app", "MyCoolApp"),
            ("my-cool-app", "MyCoolApp"),
            ("my_cool_app", "MyCoolApp"),
            ("  MyApp  ", "MyApp"),
        ]
    )
    func normalisesSeparators(input: String, expected: String) throws {
        #expect(try ProjectName(input).raw == expected)
    }

    @Test("Preserves internal capitalisation")
    func preservesAcronyms() throws {
        // Lowercasing the whole word would produce "Myapiclient".
        #expect(try ProjectName("MyAPIClient").raw == "MyAPIClient")
    }

    @Test("Splits camel case when building the slug")
    func slugSplitsCamelCase() throws {
        #expect(try ProjectName("MyCoolApp").slug == "my-cool-app")
    }

    @Test("Prefixes a leading digit, which is illegal in a module name")
    func handlesLeadingDigit() throws {
        let name = try ProjectName("123App")
        #expect(name.raw == "App123App")
        #expect(name.wasSanitized)
    }

    @Test("Records the original input so the change can be explained")
    func recordsOriginal() throws {
        let name = try ProjectName("my cool app")
        #expect(name.original == "my cool app")
        #expect(name.wasSanitized)
    }

    // MARK: - Rejection

    @Test("Rejects an empty name")
    func rejectsEmpty() {
        #expect(throws: ProjectName.ValidationError.empty) {
            try ProjectName("   ")
        }
    }

    @Test("Rejects a name with nothing usable in it")
    func rejectsPunctuationOnly() {
        #expect(throws: ProjectName.ValidationError.self) {
            try ProjectName("!!!")
        }
    }

    @Test(
        "Rejects Swift keywords and framework names",
        arguments: ["class", "import", "Swift", "SwiftUI", "Foundation"]
    )
    func rejectsReservedWords(word: String) {
        #expect(throws: ProjectName.ValidationError.self) {
            try ProjectName(word)
        }
    }

    // MARK: - Codable

    @Test("Round-trips through Codable as a plain string")
    func roundTripsThroughCodable() throws {
        let original = try ProjectName("my cool app")

        let data = try JSONEncoder().encode(original)
        #expect(String(decoding: data, as: UTF8.self) == "\"MyCoolApp\"")

        let decoded = try JSONDecoder().decode(ProjectName.self, from: data)
        #expect(decoded.raw == original.raw)
        #expect(decoded.slug == original.slug)
    }

    @Test("Decoding re-runs validation rather than trusting stored fields")
    func decodingValidates() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ProjectName.self, from: Data("\"class\"".utf8))
        }
    }
}

@Suite("ProjectName equality")
struct ProjectNameEqualityTests {

    @Test("Two names normalising to the same thing are equal")
    func equalityIgnoresInput() throws {
        // "my app" and "MyApp" name the same project; how it was typed is
        // provenance, not identity.
        #expect(try ProjectName("my app") == ProjectName("MyApp"))
        #expect(try ProjectName("my-app").hashValue == ProjectName("MyApp").hashValue)
    }

    @Test("Different names are not equal")
    func distinguishesDifferentNames() throws {
        #expect(try ProjectName("MyApp") != ProjectName("YourApp"))
    }
}

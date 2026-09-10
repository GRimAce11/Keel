import Foundation
import Testing
@testable import KeelKit

@Suite("TemplateRenderer")
struct TemplateRendererTests {

    private func makeRenderer(components: Set<Component>) throws -> TemplateRenderer {
        TemplateRenderer(
            configuration: ProjectConfiguration(
                name: try ProjectName("MyApp"),
                bundleIdentifierPrefix: "com.acme",
                components: components
            )
        )
    }

    private func render(_ text: String, components: Set<Component>) throws -> String {
        let renderer = try makeRenderer(components: components)
        let data = try #require(renderer.renderContents(of: Data(text.utf8)))
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Tokens

    @Test("Substitutes tokens in file contents")
    func substitutesTokens() throws {
        let output = try render("struct __PROJECT_NAME__App {}", components: [])
        #expect(output.contains("struct MyAppApp {}"))
    }

    @Test("Substitutes every declared token")
    func substitutesAllTokens() throws {
        let template = "__PROJECT_NAME__ __PROJECT_SLUG__ __BUNDLE_ID__ __DEPLOYMENT_TARGET__"
        let output = try render(template, components: [])

        #expect(output.contains("MyApp"))
        #expect(output.contains("my-app"))
        #expect(output.contains("com.acme.my-app"))
        #expect(output.contains("17.0"))
        // Nothing may be left unreplaced — a stray token would ship to the user.
        #expect(!output.contains("__"))
    }

    @Test("Substitutes tokens in paths and strips the .tpl suffix")
    func rendersPaths() throws {
        let renderer = try makeRenderer(components: [])
        #expect(renderer.renderPath("__PROJECT_NAME__App.swift.tpl") == "MyAppApp.swift")
        #expect(renderer.renderPath("__PROJECT_NAME__.xcodeproj") == "MyApp.xcodeproj")
    }

    @Test("Maps the __DOT__ token so dotfiles can be templated")
    func rendersDotfiles() throws {
        // The file walker skips hidden files to avoid sweeping up .DS_Store,
        // so a template for .gitignore cannot itself be named .gitignore.
        let renderer = try makeRenderer(components: [])
        #expect(renderer.renderPath("__DOT__gitignore.tpl") == ".gitignore")
    }

    @Test("Renders the date deterministically")
    func rendersDate() throws {
        let renderer = TemplateRenderer(
            configuration: ProjectConfiguration(name: try ProjectName("MyApp")),
            date: Date(timeIntervalSince1970: 1_767_225_600)   // 2026-01-01 UTC
        )
        let data = try #require(renderer.renderContents(of: Data("__YEAR__".utf8)))
        #expect(String(decoding: data, as: UTF8.self).contains("2026"))
    }

    // MARK: - Conditionals

    @Test("Keeps a block whose component is enabled")
    func keepsEnabledBlock() throws {
        let template = """
            before
            // keel:if networking
            let client = APIClient()
            // keel:end
            after
            """
        let output = try render(template, components: [.networking])
        #expect(output.contains("let client = APIClient()"))
        // Directive lines must never reach the output.
        #expect(!output.contains("keel:"))
    }

    @Test("Removes a block whose component is disabled")
    func removesDisabledBlock() throws {
        let template = """
            before
            // keel:if networking
            let client = APIClient()
            // keel:end
            after
            """
        let output = try render(template, components: [])
        #expect(!output.contains("APIClient"))
        #expect(output.contains("before"))
        #expect(output.contains("after"))
    }

    @Test("Takes the else branch when the component is off")
    func handlesElse() throws {
        let template = """
            // keel:if networking
            live
            // keel:else
            stub
            // keel:end
            """
        #expect(try render(template, components: [.networking]).contains("live"))
        #expect(try render(template, components: []).contains("stub"))
        #expect(!(try render(template, components: []).contains("live")))
    }

    @Test("Negation inverts the condition")
    func handlesNegation() throws {
        let template = """
            // keel:if !networking
            no networking here
            // keel:end
            """
        #expect(try render(template, components: []).contains("no networking here"))
        #expect(!(try render(template, components: [.networking]).contains("no networking here")))
    }

    @Test("Nested blocks resolve independently")
    func handlesNesting() throws {
        let template = """
            // keel:if exampleFeature
            // keel:if dependencyInjection
            container
            // keel:else
            direct
            // keel:end
            // keel:end
            """
        let both = try render(template, components: [.networking, .exampleFeature, .dependencyInjection])
        #expect(both.contains("container"))
        #expect(!both.contains("direct"))

        let exampleOnly = try render(template, components: [.networking, .exampleFeature])
        #expect(exampleOnly.contains("direct"))
        #expect(!exampleOnly.contains("container"))

        let neither = try render(template, components: [])
        #expect(!neither.contains("container"))
        #expect(!neither.contains("direct"))
    }

    @Test("Recognises directives behind any comment marker")
    func handlesCommentMarkers() throws {
        // A pbxproj is an old-style plist and rejects `//`; an XML scheme needs
        // `<!-- -->`. Both have to work or those files cannot be conditional.
        let template = """
            /* keel:if testing */
            pbxproj entry
            /* keel:end */
            <!-- keel:if testing -->
            scheme entry
            <!-- keel:end -->
            # keel:if testing
            shell entry
            # keel:end
            """
        let output = try render(template, components: [.testing])
        #expect(output.contains("pbxproj entry"))
        #expect(output.contains("scheme entry"))
        #expect(output.contains("shell entry"))
        #expect(!output.contains("keel:"))
    }

    @Test("An unterminated block does not lose the rest of the file")
    func toleratesUnbalancedDirectives() throws {
        // A stray keel:end with no matching if must not crash or swallow lines.
        let output = try render("kept\n// keel:end\nalso kept", components: [])
        #expect(output.contains("kept"))
        #expect(output.contains("also kept"))
    }

    // MARK: - Emptiness and binary

    @Test("A file that is entirely a disabled block renders to nothing")
    func detectsEmptyRender() throws {
        let template = """
            // keel:if exampleFeature
            everything
            // keel:end
            """
        let renderer = try makeRenderer(components: [])
        let data = try #require(renderer.renderContents(of: Data(template.utf8)))
        #expect(renderer.isEffectivelyEmpty(data))
    }

    @Test("A file with real content is not considered empty")
    func detectsNonEmptyRender() throws {
        let renderer = try makeRenderer(components: [])
        let data = try #require(renderer.renderContents(of: Data("content".utf8)))
        #expect(renderer.isEffectivelyEmpty(data) == false)
    }

    @Test("Binary content is reported so the caller copies it unchanged")
    func passesThroughBinary() throws {
        let renderer = try makeRenderer(components: [])
        // 0xFF 0xFE is not valid UTF-8, so the renderer must decline it.
        #expect(renderer.renderContents(of: Data([0xFF, 0xFE, 0x00])) == nil)
    }
}

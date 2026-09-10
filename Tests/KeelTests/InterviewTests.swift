import Foundation
import Testing
@testable import KeelKit

/// An `AnswerProvider` driven by a script instead of a person.
///
/// Recording the questions asked is half the point: a component that stops
/// being offered is a silent regression, since the developer simply never gets
/// the chance to say no.
final class ScriptedAnswers: AnswerProvider, @unchecked Sendable {

    private let textAnswers: [String: String]
    private let confirmAnswers: [String: Bool]
    private(set) var questionsAsked: [String] = []

    init(text: [String: String] = [:], confirm: [String: Bool] = [:]) {
        self.textAnswers = text
        self.confirmAnswers = confirm
    }

    func text(_ question: String, default defaultValue: String) -> String {
        questionsAsked.append(question)
        return textAnswers[question] ?? defaultValue
    }

    func confirm(_ question: String, detail: String?, default defaultValue: Bool) -> Bool {
        questionsAsked.append(question)
        return confirmAnswers[question] ?? defaultValue
    }
}

@Suite("Interview")
struct InterviewTests {

    private let console = Console(useColor: false)

    private func makeInterview(_ answers: any AnswerProvider) -> Interview {
        Interview(answers: answers, console: console)
    }

    // MARK: - Defaults

    @Test("Taking every default selects every component")
    func defaultsSelectEverything() throws {
        let configuration = makeInterview(DefaultAnswers())
            .run(name: try ProjectName("MyApp"))

        #expect(configuration.components.count == Component.allCases.count)
        #expect(configuration.minimumIOSVersion == "17.0")
        #expect(configuration.bundleIdentifier == "com.example.my-app")
    }

    @Test("Every component is offered when nothing is preselected")
    func asksAboutEveryComponent() throws {
        let answers = ScriptedAnswers()
        _ = makeInterview(answers).run(name: try ProjectName("MyApp"))

        for component in Component.allCases {
            #expect(
                answers.questionsAsked.contains(component.title),
                "should have asked about \(component.title)"
            )
        }
    }

    // MARK: - Answers

    @Test("Declining a component leaves it out")
    func declinedComponentIsExcluded() throws {
        let answers = ScriptedAnswers(confirm: [Component.networking.title: false])
        let configuration = makeInterview(answers).run(name: try ProjectName("MyApp"))

        #expect(configuration.includes(.networking) == false)
        #expect(configuration.includes(.keychain))
    }

    @Test("Declining networking also drops what depends on it")
    func decliningCascades() throws {
        let answers = ScriptedAnswers(confirm: [Component.networking.title: false])
        let configuration = makeInterview(answers).run(name: try ProjectName("MyApp"))

        #expect(configuration.includes(.exampleFeature) == false)
        #expect(configuration.includes(.authentication) == false)
        #expect(configuration.adjustments.isEmpty == false)
    }

    @Test("Typed answers are used")
    func usesTypedAnswers() throws {
        let answers = ScriptedAnswers(text: [
            "Bundle identifier prefix": "com.acme",
            "Minimum iOS version": "18.0",
        ])
        let configuration = makeInterview(answers).run(name: try ProjectName("MyApp"))

        #expect(configuration.bundleIdentifier == "com.acme.my-app")
        #expect(configuration.minimumIOSVersion == "18.0")
    }

    // MARK: - Flags win

    @Test("A preselected component is never asked about")
    func preselectionSkipsTheQuestion() throws {
        let answers = ScriptedAnswers()
        let configuration = makeInterview(answers).run(
            name: try ProjectName("MyApp"),
            preselected: [.networking: false]
        )

        #expect(configuration.includes(.networking) == false)
        #expect(answers.questionsAsked.contains(Component.networking.title) == false)
    }

    @Test("Supplied values are not asked about")
    func suppliedValuesSkipTheirQuestions() throws {
        let answers = ScriptedAnswers()
        let configuration = makeInterview(answers).run(
            name: try ProjectName("MyApp"),
            bundleIdentifierPrefix: "com.acme",
            minimumIOSVersion: "18.0"
        )

        #expect(configuration.bundleIdentifier == "com.acme.my-app")
        #expect(answers.questionsAsked.contains("Bundle identifier prefix") == false)
        #expect(answers.questionsAsked.contains("Minimum iOS version") == false)
    }

    @Test("Preselecting everything off produces an empty project")
    func minimalSelectsNothing() throws {
        let preselected = Dictionary(uniqueKeysWithValues: Component.allCases.map { ($0, false) })
        let configuration = makeInterview(ScriptedAnswers()).run(
            name: try ProjectName("MyApp"),
            preselected: preselected
        )

        #expect(configuration.components.isEmpty)
        // Nothing was requested, so nothing needed dropping.
        #expect(configuration.adjustments.isEmpty)
    }
}

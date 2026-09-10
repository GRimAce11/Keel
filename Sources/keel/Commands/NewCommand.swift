import ArgumentParser
import Foundation
import KeelKit

struct New: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Create a new iOS project."
    )

    @Argument(help: "Name of the project. Becomes the Xcode target and Swift module name.")
    var name: String

    func run() throws {
        try Unimplemented.report(
            "new",
            "It will generate an Xcode project named \(name) in the working directory."
        )
    }
}

#!/usr/bin/env swift
//
//  Draws .github/assets/demo.svg, the terminal session shown in the README.
//
//  The session below is real output, captured from `keel new` and `keel inspect`
//  on a generated project. Keeping it here rather than hand-editing the SVG
//  means the asset can be regenerated when the output changes, instead of
//  quietly drifting from what Keel actually prints — which is what happened to
//  the version this replaces.
//
//  Usage: swift Scripts/make-demo.swift .github/assets/demo.svg
//
import Foundation

// MARK: - Palette

enum Ink: String {
    case text = "#f0f6fc"
    case dim = "#8b949e"
    case green = "#3fb950"
    case cyan = "#39c5cf"
    case yellow = "#d29922"
    case purple = "#a371f7"
}

/// One run of coloured text at a fixed column.
///
/// The column is explicit rather than implied by leading spaces: SVG collapses
/// runs of whitespace, so indentation expressed as spaces slides to the margin
/// the moment it is rendered. A monospace grid is positions, so positions is
/// what this stores.
struct Span {
    let column: Int
    let text: String
    let ink: Ink
    let bold: Bool

    init(_ column: Int, _ text: String, _ ink: Ink = .text, bold: Bool = false) {
        self.column = column
        self.text = text
        self.ink = ink
        self.bold = bold
    }
}

// MARK: - The session

/// Real output. `keel inspect`'s architecture block is the part worth showing:
/// it is the thing no other tool does, and the right-hand column is the claim
/// Keel is actually making.
let session: [[Span]] = [
    [Span(0, "$ ", .green), Span(2, "keel new Bookshelf --yes")],
    [],
    [Span(0, "✓", .green), Span(2, "Wrote 48 files", .dim)],
    [Span(0, "✓", .green), Span(2, "Bookshelf is ready.", .dim)],
    [],
    [Span(0, "$ ", .green), Span(2, "keel add feature Library")],
    [],
    [Span(0, "✓", .green), Span(2, "Added Library to Bookshelf/Features/Library", .dim)],
    [],
    [Span(0, "$ ", .green), Span(2, "keel inspect")],
    [],
    [Span(0, "Architecture", .text, bold: true)],
    [Span(2, "SwiftUI MVVM, organised by feature, wired through a composition", .dim)],
    [Span(2, "root, built on @Observable, async/await and SwiftData.", .dim)],
    [],
    [Span(2, "Presentation", .dim), Span(18, "MVVM"), Span(37, "from the code", .cyan)],
    [Span(18, "8 SwiftUI views declared.", .dim)],
    [Span(18, "4 types named with a ViewModel suffix.", .dim)],
    [Span(18, "4 of those are @Observable or an ObservableObject.", .dim)],
    [Span(2, "Organisation", .dim), Span(18, "Feature-based"), Span(37, "from naming", .yellow)],
    [Span(18, "3 feature folders found.", .dim)],
    [Span(2, "Feature layers", .dim), Span(18, "Consistent"), Span(37, "from naming", .yellow)],
    [Span(18, "All 3 features are divided into Data, Domain", .dim)],
    [Span(18, "and Presentation.", .dim)],
    [Span(2, "Persistence", .dim), Span(18, "SwiftData"), Span(37, "from the code", .cyan)],
    [Span(18, "SwiftData imported by 3 files.", .dim)],
    [Span(18, "1 type marked @Model.", .dim)],
    [Span(2, "Wiring", .dim), Span(18, "Composition root"), Span(37, "from naming", .yellow)],
    [Span(18, "AppContainer declared in App/AppContainer.swift.", .dim)],
    [],
    [Span(0, "$ ", .green), Span(2, "keel check")],
    [],
    [Span(0, "✓", .green), Span(2, "Nothing to report.", .dim)],
    [Span(2, "Checked 48 Swift files against 8 rules.", .dim)],
]

// MARK: - Layout

let width = 840.0
let leftMargin = 22.0
let titleBarHeight = 36.0
let lineHeight = 21.0
let firstBaseline = 58.0
let fontSize = 13.0
/// SF Mono at 13px. Measured rather than guessed, so spans line up.
let charWidth = 7.55

let height = firstBaseline + Double(session.count) * lineHeight + 14

func escaped(_ text: String) -> String {
    text
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

var svg = """
<svg xmlns="http://www.w3.org/2000/svg" width="\(Int(width))" height="\(Int(height))" \
viewBox="0 0 \(Int(width)) \(Int(height))" role="img" \
aria-label="keel generating, extending and inspecting an iOS project">
  <rect width="\(Int(width))" height="\(Int(height))" rx="10" fill="#0d1117"/>
  <rect width="\(Int(width))" height="\(Int(titleBarHeight))" rx="10" fill="#161b22"/>
  <rect y="26" width="\(Int(width))" height="10" fill="#161b22"/>
  <circle cx="22" cy="18" r="6" fill="#ff5f57"/>
  <circle cx="42" cy="18" r="6" fill="#febc2e"/>
  <circle cx="62" cy="18" r="6" fill="#28c840"/>
  <text x="\(width / 2)" y="23" fill="#8b949e" font-size="12" text-anchor="middle" \
font-family="-apple-system, BlinkMacSystemFont, Segoe UI, sans-serif">keel</text>
  <g font-family="ui-monospace, SFMono-Regular, SF Mono, Menlo, Consolas, monospace" \
font-size="\(Int(fontSize))" xml:space="preserve">

"""

for (index, line) in session.enumerated() {
    guard !line.isEmpty else { continue }
    let y = firstBaseline + Double(index) * lineHeight

    var tspans = ""
    for span in line {
        let x = leftMargin + Double(span.column) * charWidth
        let weight = span.bold ? " font-weight=\"700\"" : ""
        tspans += "<tspan x=\"\(String(format: "%.1f", x))\" y=\"\(String(format: "%.1f", y))\" "
            + "fill=\"\(span.ink.rawValue)\"\(weight)>\(escaped(span.text))</tspan>"
    }
    svg += "    <text>\(tspans)</text>\n"
}

svg += """
  </g>
</svg>

"""

let destination = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : ".github/assets/demo.svg"
try svg.write(toFile: destination, atomically: true, encoding: .utf8)
print("Wrote \(destination) — \(Int(width))x\(Int(height))")

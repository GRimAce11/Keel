#!/usr/bin/env swift
//
//  Draws .github/assets/demo.svg, the terminal session shown in the README.
//
//  The session below is real output, captured from `keel inspect --graph` and
//  `keel check` on a project with a feature cycle in it. Nothing is reworded:
//  the only liberty taken is which sections are shown, because `--graph` prints
//  four more the image has no room for. Keeping it here rather than
//  hand-editing the SVG means the asset can be regenerated when the output
//  changes, instead of quietly drifting from what Keel actually prints — which
//  has now happened three times, most recently when findings gained a
//  `file:line` prefix, a wrapped rationale, a `[rule-id]` tag and a summary.
//
//  It shows reading a codebase rather than generating one, deliberately.
//  Generating is the contested half; reading one somebody handed you is the
//  half nothing else does.
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

/// Real output. The cycle is the part worth showing: it is the relationship an
/// import graph cannot see — both features compile into the same module, so no
/// import ever crosses between them — and every line Keel prints about it says
/// where it was read from.
let session: [[Span]] = [
    [Span(0, "$ ", .green), Span(2, "keel inspect --graph")],
    [],
    [Span(0, "Feature dependencies", .text, bold: true)],
    [Span(2, "Articles", .dim)],
    [
        Span(4, "└── Settings", .dim), Span(18, "1 link", .dim),
        Span(26, "Demo/Features/Articles/Presentation/ArticleListViewModel.swift:11", .dim),
    ],
    [Span(2, "Settings", .dim)],
    [
        Span(4, "└── Articles", .dim), Span(18, "1 link", .dim),
        Span(26, "Demo/Features/Settings/Presentation/SettingsViewModel.swift:11", .dim),
    ],
    [],
    [Span(0, "Cycles", .text, bold: true)],
    [Span(2, "feature", .dim), Span(11, "Articles → Settings → Articles", .yellow)],
    [],
    [Span(0, "$ ", .green), Span(2, "keel check")],
    [],
    [
        Span(0, "!", .yellow),
        Span(2, "Demo/Features/Articles/Presentation/ArticleListViewModel.swift:11 — Articles → Settings →"),
    ],
    [Span(2, "Articles is a dependency cycle.")],
    [Span(2, "Neither feature can be understood, moved or extracted without the other. This is the", .dim)],
    [Span(2, "relationship an import graph cannot show: in a single-target app both features compile into", .dim)],
    [Span(2, "the same module, so no import ever crosses between them and nothing else would report it.", .dim)],
    [Span(2, "Path: Articles → Settings → Articles", .dim)],
    [Span(2, "Evidence:", .dim)],
    [Span(4, "Demo/Features/Articles/Presentation/ArticleListViewModel.swift:11", .dim)],
    [Span(6, "Articles → Settings: ArticleListViewModel → SettingsViewModel  property", .dim)],
    [Span(4, "Demo/Features/Settings/Presentation/SettingsViewModel.swift:11", .dim)],
    [Span(6, "Settings → Articles: SettingsViewModel → Article  property", .dim)],
    [Span(2, "[feature-dependency-cycle]", .dim)],
    [],
    [Span(0, "Summary", .text, bold: true)],
    [Span(2, "0 errors, 1 warning", .dim)],
]

// MARK: - Layout

let leftMargin = 22.0
let titleBarHeight = 36.0
let lineHeight = 21.0
let firstBaseline = 58.0
let fontSize = 13.0
/// SF Mono at 13px, whose advance is 0.6em. Under-measuring it puts a span at
/// a column the text before it has already run past, and the two overlap —
/// which is what 7.55 did to the `property` column.
let charWidth = 7.8
/// Room for a reader whose machine has neither SF Mono nor Menlo and falls back
/// to something wider. Measured against a substituted font that came out 1.15×
/// wider than SF Mono, and rounded up from there — the asset has drifted three
/// times, and it should not also have to be eyeballed.
let substitutionAllowance = 1.2

// MARK: - Geometry

/// Two ways this image can be wrong that reading the source will not show: a
/// span placed at a column the text before it has already passed, and a line
/// that runs off the canvas. Both are arithmetic, so both are checked here
/// rather than left to whoever next opens the PNG.
for (index, line) in session.enumerated() {
    var cursor = -1
    for span in line {
        guard span.column >= cursor else {
            fatalError(
                """
                Line \(index + 1) overlaps: "\(span.text)" starts at column \(span.column), \
                which the span before it already reached. Move it right, or make the line one span.
                """
            )
        }
        cursor = span.column + span.text.count
    }
}

/// Sized to its content rather than to a number somebody picked. A line that
/// no longer fits widens the image instead of running off it.
let contentWidth = session
    .flatMap { $0 }
    .map { Double($0.column + $0.text.count) * charWidth * substitutionAllowance }
    .max() ?? 0
let width = max(840.0, (leftMargin * 2 + contentWidth).rounded(.up))

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
aria-label="keel inspect --graph and keel check reporting a feature dependency cycle">
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

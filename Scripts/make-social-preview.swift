#!/usr/bin/env swift
//
//  Draws .github/assets/social-preview.png, the repository's social preview
//  card, at GitHub's documented 1280x640.
//
//  Rendered with CoreGraphics rather than converted from an SVG: a stock macOS
//  install has no SVG rasteriser, and qlmanage gives no control over output
//  dimensions. Drawing directly also keeps the card reproducible instead of
//  being a binary nobody can regenerate.
//
//  Usage: swift Scripts/make-social-preview.swift .github/assets/social-preview.png
//
import AppKit
import CoreText

// GitHub renders social previews at 1280x640 and crops nothing, but scales the
// image down in timelines — so everything is drawn large and high contrast.
let W = 1280.0, H = 640.0
let scale = 1.0   // GitHub's documented social preview size is exactly 1280x640

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: Int(W * scale), height: Int(H * scale),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("could not create context") }

ctx.scaleBy(x: scale, y: scale)

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let ink = 0x0D1117, panel = 0x161B22, border = 0x30363D
let fg = 0xF0F6FC, muted = 0x8B949E
let blue = 0x0A84FF, green = 0x3FB950, cyan = 0x39C5CF, purple = 0x8957E5

// Background
ctx.setFillColor(rgb(UInt32(ink)))
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

// A soft blue glow behind the wordmark, so the card is not a flat rectangle.
if let glow = CGGradient(
    colorsSpace: colorSpace,
    colors: [rgb(UInt32(blue), 0.22), rgb(UInt32(blue), 0)] as CFArray,
    locations: [0, 1]
) {
    ctx.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: 250, y: H - 150), startRadius: 0,
        endCenter: CGPoint(x: 250, y: H - 150), endRadius: 560,
        options: []
    )
}

// Accent rule down the left edge.
ctx.setFillColor(rgb(UInt32(blue)))
ctx.fill(CGRect(x: 0, y: 0, width: 8, height: H))

/// Draws a line of text, positioned by its distance from the top.
@discardableResult
func draw(
    _ text: String,
    x: CGFloat, topY: CGFloat,
    size: CGFloat, weight: NSFont.Weight = .regular,
    color: UInt32, mono: Bool = false, tracking: CGFloat = 0
) -> CGFloat {
    let font = mono
        ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        : NSFont.systemFont(ofSize: size, weight: weight)

    let attributed = NSAttributedString(string: text, attributes: [
        .font: font,
        .foregroundColor: NSColor(cgColor: rgb(color))!,
        .kern: tracking,
    ])
    let line = CTLineCreateWithAttributedString(attributed)

    // CoreGraphics origin is bottom-left; callers think in distance from top.
    ctx.textPosition = CGPoint(x: x, y: H - topY)
    CTLineDraw(line, ctx)

    return CTLineGetTypographicBounds(line, nil, nil, nil)
}

func roundedRect(_ rect: CGRect, radius: CGFloat, fill: UInt32, stroke: UInt32? = nil) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(rgb(fill))
    ctx.fillPath()
    if let stroke {
        ctx.addPath(path)
        ctx.setStrokeColor(rgb(stroke))
        ctx.setLineWidth(1.5)
        ctx.strokePath()
    }
}

let left = 88.0

// Wordmark
draw("⚓", x: left, topY: 152, size: 62, color: UInt32(fg))
draw("Keel", x: left + 88, topY: 152, size: 84, weight: .bold, color: UInt32(fg), tracking: -1.5)

// Tagline, split so the important half is largest.
draw("Create, understand, and maintain",
     x: left, topY: 214, size: 30, weight: .medium, color: UInt32(muted))
draw("iOS projects from the terminal.",
     x: left, topY: 258, size: 30, weight: .medium, color: UInt32(muted))

// Terminal panel. Three lines rather than one: a single short command left the
// right half of the card empty, and the session is the product.
let panelRect = CGRect(x: left, y: H - 486, width: W - left - 88, height: 186)
roundedRect(panelRect, radius: 12, fill: UInt32(panel), stroke: UInt32(border))

// Window dots
for (i, dot) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
    ctx.setFillColor(rgb(UInt32(dot)))
    ctx.fillEllipse(in: CGRect(x: left + 22 + Double(i) * 21, y: H - 336, width: 11, height: 11))
}

/// Draws a run of differently coloured segments on one monospaced line.
func drawRun(_ segments: [(String, UInt32)], x startX: CGFloat, topY: CGFloat, size: CGFloat) {
    var x = startX
    for (text, color) in segments {
        x += draw(text, x: x, topY: topY, size: size, weight: .medium, color: color, mono: true)
    }
}

let mono = 25.0
drawRun([("$ ", UInt32(green)), ("keel new ", UInt32(fg)), ("MyApp", UInt32(cyan))],
        x: left + 26, topY: 390, size: mono)
drawRun([("? ", UInt32(cyan)), ("Networking  ", UInt32(fg)),
         ("APIClient, endpoints, typed errors  ", UInt32(muted)), ("[Y/n]", UInt32(muted))],
        x: left + 26, topY: 428, size: mono)
drawRun([("✓ ", UInt32(green)), ("MyApp is ready.", UInt32(fg))],
        x: left + 26, topY: 466, size: mono)

// Feature chips
var chipX = left
for (label, tint) in [
    ("No dependencies", green),
    ("Works offline", blue),
    ("AI optional, never automatic", purple),
] {
    let font = NSFont.systemFont(ofSize: 21, weight: .semibold)
    let width = (label as NSString).size(withAttributes: [.font: font]).width + 40

    let rect = CGRect(x: chipX, y: H - 566, width: width, height: 44)
    roundedRect(rect, radius: 22, fill: UInt32(panel), stroke: UInt32(tint))

    // Dot, then label.
    ctx.setFillColor(rgb(UInt32(tint)))
    ctx.fillEllipse(in: CGRect(x: chipX + 16, y: H - 549, width: 9, height: 9))
    draw(label, x: chipX + 33, topY: 552, size: 21, weight: .semibold, color: UInt32(fg))

    chipX += width + 16
}

// Footer
draw("Swift 6  ·  SwiftUI  ·  iOS 17+  ·  MIT",
     x: left, topY: 610, size: 19, weight: .medium, color: UInt32(muted), tracking: 0.5)

guard let image = ctx.makeImage() else { fatalError("could not render image") }
let rep = NSBitmapImageRep(cgImage: image)
rep.size = NSSize(width: W, height: H)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("could not encode PNG")
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try png.write(to: out)
print("wrote \(out.path) — \(Int(W * scale))x\(Int(H * scale)) px, displays as \(Int(W))x\(Int(H))")

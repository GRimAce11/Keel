//
//  AppLogger.swift
//  __PROJECT_NAME__
//
//  Use these instead of print(). OSLog output is visible in Console.app,
//  survives release builds, and can be filtered by category.
//

import OSLog

enum AppLogger {
    static let app     = Logger(subsystem: subsystem, category: "App")
    static let network = Logger(subsystem: subsystem, category: "Network")
    static let auth    = Logger(subsystem: subsystem, category: "Auth")
    static let data    = Logger(subsystem: subsystem, category: "Data")
    static let ui      = Logger(subsystem: subsystem, category: "UI")

    private static let subsystem = Bundle.main.bundleIdentifier ?? "__BUNDLE_ID__"
}

//
//  AppEnvironment.swift
//  __PROJECT_NAME__
//

import Foundation

enum AppEnvironment: String, Sendable {
    case development
    case production

    nonisolated static var current: AppEnvironment {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }
}

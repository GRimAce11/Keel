//
//  AppConfiguration.swift
//  __PROJECT_NAME__
//

import Foundation

/// Per-environment settings, resolved once at launch.
///
/// When the project grows past two environments, promote these values to
/// `.xcconfig` files and read them from `Bundle.main.infoDictionary`.
struct AppConfiguration: Sendable {
    let environment: AppEnvironment
    let isLoggingEnabled: Bool

    static let current: AppConfiguration = {
        switch AppEnvironment.current {
        case .development:
            return AppConfiguration(environment: .development, isLoggingEnabled: true)
        case .production:
            return AppConfiguration(environment: .production, isLoggingEnabled: false)
        }
    }()
}

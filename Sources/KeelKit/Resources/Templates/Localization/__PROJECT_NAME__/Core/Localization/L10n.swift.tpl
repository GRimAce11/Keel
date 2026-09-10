//
//  L10n.swift
//  __PROJECT_NAME__
//

import Foundation

/// Typed access to the String Catalog.
///
/// `L10n.Common.retry` instead of `"common.retry"` means a renamed or deleted
/// key fails to compile, rather than silently rendering the raw key to the
/// user at run time.
///
/// Add a case here whenever you add a key to `Localizable.xcstrings`. To
/// generate this file automatically — and to catch hardcoded strings that were
/// never localized at all — see SwiftL10n:
/// https://github.com/GRimAce11/SwiftL10n
enum L10n {

    enum App {
        static var name: String { String(localized: "app.name") }
    }

    enum Common {
        static var cancel: String { String(localized: "common.cancel") }
        static var retry: String { String(localized: "common.retry") }
        static var done: String { String(localized: "common.done") }
    }

    enum ErrorMessage {
        static var generic: String { String(localized: "error.generic") }
        static var offline: String { String(localized: "error.offline") }
    }
}

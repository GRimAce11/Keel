//
//  KeychainService.swift
//  __PROJECT_NAME__
//
//  Tokens and credentials go here. Never in UserDefaults.
//

import Foundation
import Security

// MARK: - Errors

enum KeychainError: LocalizedError, Sendable, Equatable {
    case unableToStore
    case itemNotFound
    case unableToDelete
    case unknown(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unableToStore: return "Failed to store item in keychain."
        case .itemNotFound: return "Item not found in keychain."
        case .unableToDelete: return "Failed to delete item from keychain."
        case .unknown(let status): return "Keychain error: \(status)."
        }
    }
}

// MARK: - Protocol

protocol KeychainServiceProtocol: Sendable {
    func save(_ data: Data, for key: String) throws
    func load(for key: String) throws -> Data
    func delete(for key: String) throws
    func exists(for key: String) -> Bool
}

// MARK: - Implementation

struct KeychainService: KeychainServiceProtocol, Sendable {

    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "__BUNDLE_ID__") {
        self.service = service
    }

    func save(_ data: Data, for key: String) throws {
        var query = baseQuery(for: key)
        query[kSecValueData as String] = data

        // SecItemAdd returns errSecDuplicateItem rather than overwriting, so
        // clear any existing value first. Deleting a key that is not there is
        // not an error.
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unableToStore
        }
    }

    func load(for key: String) throws -> Data {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unknown(status)
        }
        return data
    }

    func delete(for key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete
        }
    }

    func exists(for key: String) -> Bool {
        (try? load(for: key)) != nil
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            // Readable after the first unlock following a reboot, and never
            // carried to another device by a backup restore.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
    }
}

// MARK: - Convenience

extension KeychainServiceProtocol {
    func saveString(_ string: String, for key: String) throws {
        try save(Data(string.utf8), for: key)
    }

    func loadString(for key: String) throws -> String {
        guard let string = String(data: try load(for: key), encoding: .utf8) else {
            throw KeychainError.itemNotFound
        }
        return string
    }
}

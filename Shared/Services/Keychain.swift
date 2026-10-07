//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import KeychainSwift
import Security

extension Container {

    // TODO: take a look at all security options
    var keychainService: Factory<CouchfinKeychain> {
        self { CouchfinKeychain() }.singleton
    }
}

/// The app's keychain: strings by key.
///
/// On tvOS, items live in the **user-independent** keychain, so every Apple TV
/// profile shares the household's server logins, PINs and Seerr sessions while the
/// rest of the app's data is kept per profile (see `HouseholdStore`). Items written
/// by earlier versions (in the per-profile keychain) are moved over the first time
/// they're read. When the user-independent keychain is unavailable (the entitlement
/// is missing), it falls back to the regular keychain.
///
/// On iOS this is the regular keychain, exactly as before.
final class CouchfinKeychain {

    private let legacy = KeychainSwift()

    func get(_ key: String) -> String? {
        #if os(tvOS)
        if let value = shared(key) {
            return value
        }

        guard let value = legacy.get(key) else { return nil }

        // move it over, so other Apple TV profiles can see it
        if setShared(value, forKey: key) {
            legacy.delete(key)
        }

        return value
        #else
        legacy.get(key)
        #endif
    }

    @discardableResult
    func set(_ value: String, forKey key: String) -> Bool {
        #if os(tvOS)
        if setShared(value, forKey: key) {
            legacy.delete(key)
            return true
        }
        #endif

        return legacy.set(value, forKey: key)
    }

    @discardableResult
    func delete(_ key: String) -> Bool {
        #if os(tvOS)
        let sharedDeleted = deleteShared(key)
        let legacyDeleted = legacy.delete(key)
        return sharedDeleted || legacyDeleted
        #else
        legacy.delete(key)
        #endif
    }

    // MARK: - User-independent keychain (tvOS)

    #if os(tvOS)
    private static let service = "land.sams.couchfin.household"

    private func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key,
            kSecUseUserIndependentKeychain as String: kCFBooleanTrue as Any,
        ]
    }

    private func shared(_ key: String) -> String? {
        var query = query(key)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }

        return String(data: data, encoding: .utf8)
    }

    private func setShared(_ value: String, forKey key: String) -> Bool {
        let data = Data(value.utf8)
        let query = query(key)

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return true
        }

        guard updateStatus == errSecItemNotFound else { return false }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private func deleteShared(_ key: String) -> Bool {
        SecItemDelete(query(key) as CFDictionary) == errSecSuccess
    }
    #endif
}

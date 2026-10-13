import CryptoKit

/// `SymmetricKey` wrapper that is explicitly `Sendable` so keys can cross actor boundaries.
package struct SymmetricKeyBox: Sendable {
    package let key: SymmetricKey

    package init(_ key: SymmetricKey) {
        self.key = key
    }
}

import CryptoKit

/// `SymmetricKey` wrapper that is explicitly `Sendable` so keys can cross actor boundaries.
struct SymmetricKeyBox: Sendable {
    let key: SymmetricKey

    init(_ key: SymmetricKey) {
        self.key = key
    }
}

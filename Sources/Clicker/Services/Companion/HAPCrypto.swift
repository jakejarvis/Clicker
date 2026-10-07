import CryptoKit
import Foundation

/// Primitives shared by HomeKit-style pair-setup, pair-verify and the
/// encrypted Companion session.
enum HAPCrypto {
    /// HKDF-SHA512 with the string salt/info labels used throughout HAP.
    static func deriveKey(salt: String, info: String, sharedSecret: Data) -> SymmetricKey {
        HKDF<SHA512>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: sharedSecret),
            salt: Data(salt.utf8),
            info: Data(info.utf8),
            outputByteCount: 32
        )
    }

    /// Pairing messages use fixed eight-byte labels such as "PS-Msg05" as the
    /// nonce, left-padded with zeros to the 12 bytes ChaCha20-Poly1305 needs.
    static func nonce(label: String) -> Data {
        let bytes = Data(label.utf8)
        precondition(bytes.count <= 12, "nonce label too long")
        return Data(count: 12 - bytes.count) + bytes
    }

    /// Returns ciphertext followed by the 16-byte authentication tag.
    static func seal(_ plaintext: Data, key: SymmetricKey, nonce: Data, aad: Data = Data()) throws -> Data {
        let box = try ChaChaPoly.seal(
            plaintext,
            using: key,
            nonce: ChaChaPoly.Nonce(data: nonce),
            authenticating: aad
        )
        // Copy so callers get a zero-based Data rather than a slice.
        return Data(box.ciphertext) + Data(box.tag)
    }

    /// Opens ciphertext + 16-byte tag produced by `seal`.
    static func open(_ sealed: Data, key: SymmetricKey, nonce: Data, aad: Data = Data()) throws -> Data {
        guard sealed.count >= 16 else { throw CompanionError.encryptionFailed }
        let box = try ChaChaPoly.SealedBox(
            nonce: ChaChaPoly.Nonce(data: nonce),
            ciphertext: sealed.dropLast(16),
            tag: sealed.suffix(16)
        )
        return try ChaChaPoly.open(box, using: key, authenticating: aad)
    }
}

/// Encryption state for an established Companion session: separate keys per
/// direction, each with its own message counter used as a 12-byte
/// little-endian nonce.
struct SessionCipher: Sendable {
    private let outputKey: SymmetricKey
    private let inputKey: SymmetricKey
    private var outputCounter: UInt64 = 0
    private var inputCounter: UInt64 = 0

    init(outputKey: SymmetricKey, inputKey: SymmetricKey) {
        self.outputKey = outputKey
        self.inputKey = inputKey
    }

    mutating func encrypt(_ plaintext: Data, aad: Data) throws -> Data {
        let nonce = Self.nonce(counter: outputCounter)
        outputCounter += 1
        return try HAPCrypto.seal(plaintext, key: outputKey, nonce: nonce, aad: aad)
    }

    mutating func decrypt(_ sealed: Data, aad: Data) throws -> Data {
        let nonce = Self.nonce(counter: inputCounter)
        inputCounter += 1
        return try HAPCrypto.open(sealed, key: inputKey, nonce: nonce, aad: aad)
    }

    private static func nonce(counter: UInt64) -> Data {
        var nonce = Data(count: 12)
        for shift in 0..<8 {
            nonce[shift] = UInt8(truncatingIfNeeded: counter >> (8 * UInt64(shift)))
        }
        return nonce
    }
}

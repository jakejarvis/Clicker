import BigInt
import CryptoKit
import Foundation

/// SRP-6a client in the HomeKit flavor: RFC 5054 3072-bit group, SHA-512,
/// `k = H(N | PAD(g))`, `u = H(PAD(A) | PAD(B))`, and the RFC 2945 proofs.
struct SRPClient {
    struct Session: Sendable {
        /// `M1`, sent to the accessory.
        let clientProof: Data
        /// `M2`, which the accessory must echo back.
        let expectedServerProof: Data
        /// `K`, the shared session key used to derive the pairing keys.
        let sessionKey: Data
    }

    enum Failure: Error {
        case invalidServerPublicKey
        case invalidScrambler
    }

    static let prime = BigUInt(
        "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DD"
            + "EF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED"
            + "EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F"
            + "83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3B"
            + "E39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497CEA956AE515D2261898FA0510"
            + "15728E5A8AAAC42DAD33170D04507A33A85521ABDF1CBA64ECFB850458DBEF0A8AEA71575D060C7DB3970F85A6E1E4C7"
            + "ABF5AE8CDB0933D71E8C94E04A25619DCEE3D2261AD2EE6BF12FFA06D98A0864D87602733EC86A64521F2B18177B200C"
            + "BBE117577A615D6C770988C0BAD946E208E24FA074E5AB3143DB5BFCE0FD108E4B82D120A93AD2CAFFFFFFFFFFFFFFFF",
        radix: 16
    )!
    static let generator = BigUInt(5)
    static let keyLength = 384

    private let privateKey: BigUInt
    private let publicKeyValue: BigUInt

    init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        var generator = SystemRandomNumberGenerator()
        for index in bytes.indices { bytes[index] = generator.next() }
        self.init(privateKey: BigUInt(Data(bytes)))
    }

    init(privateKey: BigUInt) {
        self.privateKey = privateKey
        self.publicKeyValue = Self.generator.power(privateKey, modulus: Self.prime)
    }

    /// `A`, padded to the group size.
    var publicKey: Data {
        Self.pad(publicKeyValue)
    }

    func process(serverPublicKey: Data, salt: Data, username: String = "Pair-Setup", password: String) throws -> Session {
        let N = Self.prime
        let g = Self.generator
        let A = publicKeyValue
        let B = BigUInt(serverPublicKey)
        guard B % N != 0 else { throw Failure.invalidServerPublicKey }

        let k = BigUInt(Self.hash(Self.pad(N), Self.pad(g)))
        let identityHash = Self.hash(Data("\(username):\(password)".utf8))
        let x = BigUInt(Self.hash(salt, identityHash))
        let u = BigUInt(Self.hash(Self.pad(A), Self.pad(B)))
        guard u != 0 else { throw Failure.invalidScrambler }

        let v = g.power(x, modulus: N)
        let kv = (k * v) % N
        let base = (B % N + N - kv) % N
        let exponent = privateKey + u * x
        let S = base.power(exponent, modulus: N)
        let K = Self.hash(S.serialize())

        let hashN = Self.hash(N.serialize())
        let hashG = Self.hash(g.serialize())
        let xored = Data(zip(hashN, hashG).map { $0 ^ $1 })
        let M1 = Self.hash(
            xored,
            Self.hash(Data(username.utf8)),
            salt,
            A.serialize(),
            B.serialize(),
            K
        )
        let M2 = Self.hash(A.serialize(), M1, K)

        return Session(clientProof: M1, expectedServerProof: M2, sessionKey: K)
    }

    static func hash(_ parts: Data...) -> Data {
        var hasher = SHA512()
        for part in parts { hasher.update(data: part) }
        return Data(hasher.finalize())
    }

    static func pad(_ value: BigUInt) -> Data {
        let bytes = value.serialize()
        guard bytes.count < keyLength else { return bytes }
        return Data(count: keyLength - bytes.count) + bytes
    }
}

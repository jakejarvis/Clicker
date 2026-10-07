import BigInt
import CryptoKit
import Foundation
import Testing
@testable import Clicker

@Suite struct CryptoTests {
    @Test func sessionCipherRoundTripsWithCounters() throws {
        let key = SymmetricKey(size: .bits256)
        var sender = SessionCipher(outputKey: key, inputKey: key)
        var receiver = SessionCipher(outputKey: key, inputKey: key)
        let header = Data([0x08, 0, 0, 21])

        let first = try sender.encrypt(Data("hello".utf8), aad: header)
        let second = try sender.encrypt(Data("world".utf8), aad: header)
        #expect(first.count == 5 + 16)
        #expect(try receiver.decrypt(first, aad: header) == Data("hello".utf8))
        #expect(try receiver.decrypt(second, aad: header) == Data("world".utf8))

        // Replaying the first message fails because the counter has advanced.
        #expect(throws: (any Error).self) { try receiver.decrypt(first, aad: header) }
    }

    @Test func pairingNonceIsLeftPadded() {
        #expect(HAPCrypto.nonce(label: "PS-Msg05") == Data([0, 0, 0, 0]) + Data("PS-Msg05".utf8))
    }

    @Test func sealAndOpenWithLabelNonce() throws {
        let key = HAPCrypto.deriveKey(salt: "Pair-Setup-Encrypt-Salt", info: "Pair-Setup-Encrypt-Info", sharedSecret: Data(repeating: 9, count: 64))
        let sealed = try HAPCrypto.seal(Data([1, 2, 3]), key: key, nonce: HAPCrypto.nonce(label: "PS-Msg05"))
        #expect(try HAPCrypto.open(sealed, key: key, nonce: HAPCrypto.nonce(label: "PS-Msg05")) == Data([1, 2, 3]))
        #expect(throws: (any Error).self) {
            try HAPCrypto.open(sealed, key: key, nonce: HAPCrypto.nonce(label: "PS-Msg06"))
        }
    }

    /// Simulates the accessory side of SRP-6a (RFC 5054 group, SHA-512) and
    /// checks that both proofs agree with the client.
    @Test func srpClientAgreesWithServer() throws {
        let N = SRPClient.prime
        let g = SRPClient.generator
        let pin = "1234"
        let salt = Data((0..<16).map { UInt8($0 * 7 + 1) })

        let x = BigUInt(SRPClient.hash(salt, SRPClient.hash(Data("Pair-Setup:\(pin)".utf8))))
        let v = g.power(x, modulus: N)
        let k = BigUInt(SRPClient.hash(SRPClient.pad(N), SRPClient.pad(g)))
        let b = BigUInt(Data((0..<32).map { UInt8($0 + 100) }))
        let B = (k * v + g.power(b, modulus: N)) % N

        let client = SRPClient()
        let session = try client.process(serverPublicKey: SRPClient.pad(B), salt: salt, password: pin)

        let A = BigUInt(client.publicKey)
        let u = BigUInt(SRPClient.hash(SRPClient.pad(A), SRPClient.pad(B)))
        let S = (A * v.power(u, modulus: N)).power(b, modulus: N)
        let K = SRPClient.hash(S.serialize())
        let hashN = SRPClient.hash(N.serialize())
        let hashG = SRPClient.hash(g.serialize())
        let xored = Data(zip(hashN, hashG).map { $0 ^ $1 })
        let M1 = SRPClient.hash(xored, SRPClient.hash(Data("Pair-Setup".utf8)), salt, A.serialize(), B.serialize(), K)
        let M2 = SRPClient.hash(A.serialize(), M1, K)

        #expect(session.sessionKey == K)
        #expect(session.clientProof == M1)
        #expect(session.expectedServerProof == M2)
        #expect(client.publicKey.count == 384)
    }

    @Test func srpRejectsZeroServerKey() {
        let client = SRPClient()
        #expect(throws: SRPClient.Failure.invalidServerPublicKey) {
            try client.process(serverPublicKey: Data(count: 384), salt: Data(count: 16), password: "0000")
        }
    }
}

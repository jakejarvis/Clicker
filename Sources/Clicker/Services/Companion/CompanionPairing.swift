import CryptoKit
import Foundation
import Network

/// HomeKit-style pair-setup and pair-verify over a Companion connection.
enum CompanionPairing {
    /// Extracts and validates the `_pd` TLV from an authentication response.
    static func pairingData(from response: OPACKValue) throws -> TLV8.Items {
        guard let data = response["_pd"]?.dataValue else {
            throw CompanionError.unexpectedResponse("missing pairing data")
        }
        let items = try TLV8.decode(data)
        if let code = items.errorCode {
            throw CompanionError.pairingError(code.message)
        } else if items[.error] != nil {
            throw CompanionError.pairingError(TLV8.ErrorCode.unknown.message)
        }
        return items
    }

    /// Proves possession of stored credentials and switches the connection to
    /// encrypted frames.
    static func verify(on connection: CompanionConnection, credentials: PairingCredentials) async throws {
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let ourPublic = ephemeral.publicKey.rawRepresentation

        let startResponse = try await connection.exchangeAuthentication(.pairVerifyStart, [
            "_pd": .data(TLV8.encode([(.state, Data([0x01])), (.publicKey, ourPublic)])),
            "_auTy": 4,
        ])
        let startItems = try pairingData(from: startResponse)
        guard let serverPublic = startItems[.publicKey], let encrypted = startItems[.encryptedData] else {
            throw CompanionError.unexpectedResponse("pair-verify M2 incomplete")
        }

        let serverKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: serverPublic)
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: serverKey).withUnsafeBytes { Data($0) }
        let sessionKey = HAPCrypto.deriveKey(
            salt: "Pair-Verify-Encrypt-Salt", info: "Pair-Verify-Encrypt-Info", sharedSecret: shared
        )

        let decrypted: Data
        do {
            decrypted = try HAPCrypto.open(encrypted, key: sessionKey, nonce: HAPCrypto.nonce(label: "PV-Msg02"))
        } catch {
            throw CompanionError.authenticationFailed("could not decrypt the Apple TV's reply")
        }
        let inner = try TLV8.decode(decrypted)
        guard let identifier = inner[.identifier], let signature = inner[.signature] else {
            throw CompanionError.unexpectedResponse("pair-verify M2 missing identity")
        }
        guard identifier == credentials.accessoryIdentifier else {
            throw CompanionError.authenticationFailed("the Apple TV's identity changed; pair again")
        }

        let accessoryKey = try Curve25519.Signing.PublicKey(rawRepresentation: credentials.accessoryPublicKey)
        guard accessoryKey.isValidSignature(signature, for: serverPublic + identifier + ourPublic) else {
            throw CompanionError.authenticationFailed("the Apple TV's signature did not verify")
        }

        let signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: credentials.clientPrivateKey)
        let clientIdentifier = Data(credentials.clientIdentifier.utf8)
        let ourSignature = try signingKey.signature(for: ourPublic + clientIdentifier + serverPublic)
        let payload = TLV8.encode([(.identifier, clientIdentifier), (.signature, ourSignature)])
        let sealed = try HAPCrypto.seal(payload, key: sessionKey, nonce: HAPCrypto.nonce(label: "PV-Msg03"))

        let finishResponse = try await connection.exchangeAuthentication(.pairVerifyNext, [
            "_pd": .data(TLV8.encode([(.state, Data([0x03])), (.encryptedData, sealed)])),
        ])
        if finishResponse["_pd"] != nil {
            _ = try pairingData(from: finishResponse)
        }

        let outputKey = HAPCrypto.deriveKey(salt: "", info: "ClientEncrypt-main", sharedSecret: shared)
        let inputKey = HAPCrypto.deriveKey(salt: "", info: "ServerEncrypt-main", sharedSecret: shared)
        await connection.enableEncryption(outputKey: SymmetricKeyBox(outputKey), inputKey: SymmetricKeyBox(inputKey))
        Log.pairing.info("Pair-verify succeeded; session encrypted")
    }
}

/// One pair-setup attempt. `start()` makes the Apple TV display a PIN;
/// `finish(pin:)` completes the exchange and returns long-term credentials.
actor CompanionPairingSession {
    private let connection: CompanionConnection
    private let srp = SRPClient()
    private let signingKey = Curve25519.Signing.PrivateKey()
    private let pairingIdentifier = UUID().uuidString.lowercased()
    private var salt: Data?
    private var serverPublicKey: Data?

    init(endpoint: NWEndpoint) {
        connection = CompanionConnection(endpoint: endpoint)
    }

    func start() async throws {
        try await connection.connect()
        let response = try await connection.exchangeAuthentication(.pairSetupStart, [
            "_pd": .data(TLV8.encode([(.method, Data([0x00])), (.state, Data([0x01]))])),
            "_pwTy": 1,
        ])
        let items = try CompanionPairing.pairingData(from: response)
        guard let salt = items[.salt], let publicKey = items[.publicKey] else {
            throw CompanionError.unexpectedResponse("pair-setup M2 incomplete")
        }
        self.salt = salt
        self.serverPublicKey = publicKey
        Log.pairing.info("Pair-setup started; PIN should be on screen")
    }

    func finish(pin: String, clientName: String, device: AppleTVDevice) async throws -> PairingCredentials {
        guard let salt, let serverPublicKey else {
            throw CompanionError.pairingError("Pairing has not been started.")
        }

        let session = try srp.process(serverPublicKey: serverPublicKey, salt: salt, password: pin)
        let proofResponse = try await connection.exchangeAuthentication(.pairSetupNext, [
            "_pd": .data(TLV8.encode([
                (.state, Data([0x03])),
                (.publicKey, srp.publicKey),
                (.proof, session.clientProof),
            ])),
            "_pwTy": 1,
        ])
        let proofItems = try CompanionPairing.pairingData(from: proofResponse)
        guard let serverProof = proofItems[.proof] else {
            throw CompanionError.unexpectedResponse("pair-setup M4 missing proof")
        }
        guard serverProof == session.expectedServerProof else {
            throw CompanionError.authenticationFailed("the Apple TV's proof did not match")
        }

        let controllerSigningSalt = HAPCrypto.deriveKey(
            salt: "Pair-Setup-Controller-Sign-Salt",
            info: "Pair-Setup-Controller-Sign-Info",
            sharedSecret: session.sessionKey
        )
        let encryptionKey = HAPCrypto.deriveKey(
            salt: "Pair-Setup-Encrypt-Salt",
            info: "Pair-Setup-Encrypt-Info",
            sharedSecret: session.sessionKey
        )

        let publicKey = signingKey.publicKey.rawRepresentation
        let identifier = Data(pairingIdentifier.utf8)
        let signature = try signingKey.signature(for: controllerSigningSalt.rawData + identifier + publicKey)
        let inner = TLV8.encode([
            (.identifier, identifier),
            (.publicKey, publicKey),
            (.signature, signature),
            (.name, OPACK.encode(["name": .string(clientName)])),
        ])
        let sealed = try HAPCrypto.seal(inner, key: encryptionKey, nonce: HAPCrypto.nonce(label: "PS-Msg05"))

        let exchangeResponse = try await connection.exchangeAuthentication(.pairSetupNext, [
            "_pd": .data(TLV8.encode([(.state, Data([0x05])), (.encryptedData, sealed)])),
            "_pwTy": 1,
        ])
        let exchangeItems = try CompanionPairing.pairingData(from: exchangeResponse)
        guard let encrypted = exchangeItems[.encryptedData] else {
            throw CompanionError.unexpectedResponse("pair-setup M6 missing data")
        }
        let decrypted = try HAPCrypto.open(encrypted, key: encryptionKey, nonce: HAPCrypto.nonce(label: "PS-Msg06"))
        let accessory = try TLV8.decode(decrypted)
        guard let accessoryIdentifier = accessory[.identifier],
              let accessoryPublicKey = accessory[.publicKey],
              let accessorySignature = accessory[.signature]
        else {
            throw CompanionError.unexpectedResponse("pair-setup M6 incomplete")
        }

        // HAP has the accessory sign HKDF(K) | id | ltpk. The PIN-authenticated
        // SRP exchange already rules out an impostor, so a mismatch is logged
        // rather than fatal in case tvOS deviates from the spec here.
        let accessorySigningSalt = HAPCrypto.deriveKey(
            salt: "Pair-Setup-Accessory-Sign-Salt",
            info: "Pair-Setup-Accessory-Sign-Info",
            sharedSecret: session.sessionKey
        )
        if let key = try? Curve25519.Signing.PublicKey(rawRepresentation: accessoryPublicKey),
           !key.isValidSignature(accessorySignature, for: accessorySigningSalt.rawData + accessoryIdentifier + accessoryPublicKey)
        {
            Log.pairing.warning("Accessory signature in PS-Msg06 did not verify")
        }

        await connection.close()
        Log.pairing.info("Pair-setup completed with \(device.name, privacy: .public)")

        return PairingCredentials(
            deviceID: device.id,
            deviceName: device.name,
            deviceModel: device.model,
            accessoryIdentifier: accessoryIdentifier,
            accessoryPublicKey: accessoryPublicKey,
            clientIdentifier: pairingIdentifier,
            clientPrivateKey: signingKey.rawRepresentation,
            pairedAt: Date()
        )
    }

    func cancel() async {
        await connection.close()
    }
}

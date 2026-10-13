import CryptoKit
import Foundation

extension SymmetricKey {
    package var rawData: Data {
        withUnsafeBytes { Data($0) }
    }
}

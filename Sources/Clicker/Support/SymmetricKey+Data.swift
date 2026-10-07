import CryptoKit
import Foundation

extension SymmetricKey {
    var rawData: Data {
        withUnsafeBytes { Data($0) }
    }
}

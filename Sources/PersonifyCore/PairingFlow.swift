import Foundation

/// How a room connection starts. A saved code is used with no sheet.
public enum SilentConnect: Equatable, Sendable {
    case savedPIN(String)
    case withoutPIN
}

/// Why the small pairing sheet is on screen.
public enum PairingSheetTrigger: Equatable, Sendable {
    case authenticationFailed
    case pinRequired
}

public enum PairingFlow {
    /// Empty and missing codes connect without a PIN. A saved code is sent as-is.
    public static func initialConnect(savedPIN: String?) -> SilentConnect {
        let trimmed = savedPIN?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return .withoutPIN }
        return .savedPIN(trimmed)
    }

    /// The sheet is for a failed authentication, or for a device that asked for a code when none is saved.
    /// A saved code answers a PIN request without a sheet.
    public static func sheetTrigger(savedPIN: String?, authenticationFailed: Bool, deviceRequestedPIN: Bool) -> PairingSheetTrigger? {
        if authenticationFailed { return .authenticationFailed }
        let saved = savedPIN?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if deviceRequestedPIN && saved.isEmpty { return .pinRequired }
        return nil
    }

    /// CoreBluetooth and ATT codes that mean the link needs a pairing code.
    /// CBError 14 is peerRemovedPairingInformation, 15 is encryptionTimedOut.
    /// ATT 5 is insufficientAuthentication, 15 is insufficientEncryption.
    public static func isAuthenticationFailure(domain: String, code: Int) -> Bool {
        switch domain {
        case "CBErrorDomain":
            return code == 14 || code == 15
        case "CBATTErrorDomain":
            return code == 5 || code == 15
        default:
            return false
        }
    }
}

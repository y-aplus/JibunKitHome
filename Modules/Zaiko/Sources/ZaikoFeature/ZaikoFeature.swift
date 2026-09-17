import Foundation

/// Host-supplied storage keys. JibunKit builds them from its own namespace
/// (`MiniAppContext.storageKey(_:)`); the Feature never resolves the shared
/// suite by itself and never composes another Feature's keys.
public struct ZaikoStorageKeys: Sendable {
    public let state: String
    public let backupLatest: String
    public let backupPrevious: String

    public init(state: String, backupLatest: String, backupPrevious: String) {
        self.state = state
        self.backupLatest = backupLatest
        self.backupPrevious = backupPrevious
    }
}

/// Host-supplied notification naming. Zaiko owns stable per-item keys; the host
/// maps a key to a notification request identifier and decides ownership, so the
/// Feature does not depend on the host's identifier format.
public struct ZaikoNotificationNamespace: Sendable {
    public let requestIdentifier: @Sendable (String) -> String
    public let owns: @Sendable (String) -> Bool
    public let userInfo: [String: String]

    public init(
        requestIdentifier: @escaping @Sendable (String) -> String,
        owns: @escaping @Sendable (String) -> Bool,
        userInfo: [String: String]
    ) {
        self.requestIdentifier = requestIdentifier
        self.owns = owns
        self.userInfo = userInfo
    }
}

/// Resolving the storage location is the host's responsibility. An unavailable
/// location stays a state the screen reports; the Feature never writes to a
/// different store instead.
public enum ZaikoStorageError: LocalizedError, Equatable, Sendable {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let description):
            return description
        }
    }
}

/// Backup validation lives with the Feature that owns the format. The host calls
/// this before asking the user to confirm an overwrite; it changes nothing.
public enum ZaikoBackupDocument {
    public static func validate(_ data: Data) throws {
        _ = try ZaikoBackup.decode(data)
    }
}

public enum ZaikoBackupError: LocalizedError, Equatable, Sendable {
    case unsupportedSchema(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "対応していないバックアップ形式です (schema \(version))。"
        }
    }
}

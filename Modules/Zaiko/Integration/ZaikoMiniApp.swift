#if os(iOS)
import Foundation
import JibunKitCore
import ZaikoFeature

/// Host-side connection for the Zaiko Feature. The Feature package does not
/// depend on JibunKitCore, so this file owns the naming that comes from the
/// host: storage keys, notification request identifiers, payloads, and the
/// management contracts (backup, removal, permission).
public extension MiniAppID {
    static let zaiko = MiniAppID("zaiko")
}

@MainActor
public enum ZaikoMiniApp {
    public static let id = MiniAppID("zaiko")
    public static let lifetime = MiniAppFeatureLifetime(id: id)

    /// Schema 3 is the standalone app's current envelope version.
    static let schemaVersion = 3

    static let notificationPermission = MiniAppPermissionDeclaration(
        id: "notifications",
        title: "通知",
        purpose: "在庫が補充タイミングに入ったときに通知します。",
        deniedBehavior: "在庫の登録・計算・バックアップは引き続き利用できます。")

    private static let context = MiniAppContext(id: id)

    private static let store: ZaikoStore = makeStore()

    private static func makeStore() -> ZaikoStore {
        let context = MiniAppContext(id: id)
        let keys = ZaikoStorageKeys(
            state: context.storageKey("state"),
            backupLatest: context.storageKey("backup.latest"),
            backupPrevious: context.storageKey("backup.prev")
        )
        let notifications = ZaikoNotificationNamespace(
            requestIdentifier: { context.notificationRequestIdentifier(for: $0) },
            owns: { context.ownsNotificationRequestIdentifier($0) },
            userInfo: context.notificationUserInfo
        )
        do {
            return ZaikoStore(
                defaults: try MiniAppStorage.sharedDefaults(),
                keys: keys,
                notifications: notifications
            )
        } catch {
            // The screen reports the unavailable suite; the store never writes
            // to a different location instead.
            return ZaikoStore(
                defaults: nil,
                keys: keys,
                notifications: notifications,
                configurationError: .unavailable("在庫の保存先を開けません: \(error.localizedDescription)")
            )
        }
    }

    private static let backup: MiniAppBackupProvider = {
        let owner = id
        let schema = schemaVersion
        return MiniAppBackupProvider(id: owner, export: {
            let json = await MainActor.run { ZaikoMiniApp.store.exportBackupJSON() }
            return MiniAppBackupEntry(id: owner, schemaVersion: schema, payload: Data(json.utf8))
        }, prepare: { entry in
            guard entry.schemaVersion == schema else {
                throw ZaikoBackupError.unsupportedSchema(entry.schemaVersion)
            }
            // Validate on the host side before the user confirms; applying the
            // same payload again re-decodes it, so a changed file cannot land
            // halfway.
            let payload = entry.payload
            try ZaikoBackupDocument.validate(payload)
            return MiniAppPreparedRestore {
                try await MainActor.run { try ZaikoMiniApp.store.importBackup(data: payload) }
            }
        })
    }()

    private static let removal = MiniAppRemovalProvider(
        id: id,
        dataDescription: "在庫データ（品目・設定・バックアップ）",
        removeData: { await MainActor.run { ZaikoMiniApp.store.removeOwnedData() } })

    public static let definition = MiniAppDefinition(
        id: id,
        title: "在庫管理",
        systemImage: "shippingbox",
        backup: backup,
        lifetime: lifetime,
        removal: removal,
        permissions: [notificationPermission]
    ) { _ in
        ZaikoRootView(store: store)
    }
}
#endif

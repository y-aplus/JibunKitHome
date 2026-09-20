import Foundation

/// Logical Feature IDs remain stable; only the OS-facing task name follows a
/// re-signed bundle. The original ID is written by the host at build time.
enum MiniAppBackgroundTaskIdentifier {
    static func resolve(_ identifier: String,
                        info: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> String {
        guard let original = info["JibunKitOriginalBundleIdentifier"] as? String,
              let installed = info["CFBundleIdentifier"] as? String,
              !original.isEmpty, !installed.isEmpty, original != installed,
              identifier.hasPrefix(original + "."),
              let permitted = info["BGTaskSchedulerPermittedIdentifiers"] as? [String] else {
            return identifier
        }
        if identifier.hasPrefix(installed + ".") { return identifier }
        let candidate = installed + identifier.dropFirst(original.count)
        // Only use a rewritten name actually authorized by the installed plist.
        // An unrelated suffix, another owner's name, or a stale list is not a map.
        let matches = permitted.contains { entry in
            entry == candidate || (entry.hasSuffix(".*")
                && candidate.hasPrefix(String(entry.dropLast()))
                && candidate.count > entry.count - 1)
        }
        return matches ? candidate : identifier
    }
}

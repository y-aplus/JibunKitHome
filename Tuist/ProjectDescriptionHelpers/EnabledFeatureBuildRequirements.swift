/// Register build requirements beside the native target's Feature dependencies.
/// Runtime MiniAppDefinition cannot change a built app's plist or entitlements.
public enum EnabledFeatureBuildRequirements {
    public static let app = FeatureBuildConfiguration()
    public static let widget = FeatureBuildConfiguration()
    /// Opt in only when this host includes the incoming Action Extension.
    public static let action: FeatureBuildConfiguration? = nil
}

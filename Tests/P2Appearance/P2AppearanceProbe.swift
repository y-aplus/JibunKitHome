#if os(iOS)
import JibunKitCore
import Observation
import SwiftUI
import UIKit

@MainActor
enum P2AppearanceProbe {
    static let first = P2AppearanceFeature(id: MiniAppID("p2-appearance-a"), title: "Appearance A", scheme: .dark)
    static let second = P2AppearanceFeature(id: MiniAppID("p2-appearance-b"), title: "Appearance B", scheme: .light)
    static let definitions = [first.definition, second.definition]
}

@MainActor @Observable
final class P2AppearanceFeature {
    let id: MiniAppID
    let title: String
    let scheme: ColorScheme
    var requested = false
    var effective = false
    var rootEnvironment = "unread"
    var rootTrait = "unread"
    var sheetEnvironment = "closed"
    var sheetTrait = "closed"
    var showingSheet = false

    @ObservationIgnored private let timer: MiniAppIdleTimer
    @ObservationIgnored private let runtimeHolder: P2AppearanceRuntimeHolder
    @ObservationIgnored private var sceneIdle: MiniAppSceneIdleTimer?
    @ObservationIgnored private var sceneActivities: [UUID: MiniAppSceneActivity] = [:]
    @ObservationIgnored let lifetime: MiniAppFeatureLifetime

    init(id: MiniAppID, title: String, scheme: ColorScheme, timer: MiniAppIdleTimer = .shared) {
        let holder = P2AppearanceRuntimeHolder()
        self.id = id
        self.title = title
        self.scheme = scheme
        self.timer = timer
        runtimeHolder = holder
        lifetime = MiniAppFeatureLifetime(id: id) { [holder] runtime in
            try holder.configure(runtime)
        }
        holder.feature = self
    }

    var definition: MiniAppDefinition {
        MiniAppDefinition(
            id: id, title: title, systemImage: "circle.lefthalf.filled", lifetime: lifetime,
            onSceneActivityChange: { [weak self] in self?.receive($0) }
        ) { [self] _ in
            P2AppearanceRoot(feature: self, policy: .environment(scheme))
        }
    }

    func setRequested(_ value: Bool) {
        requested = value
        do { try sceneIdle?.setRequested(value) }
        catch { requested = false }
        refreshEffective()
    }

    func receive(_ activity: MiniAppSceneActivity) {
        guard activity.featureID == id else { return }
        if activity.isConnected { sceneActivities[activity.sceneID] = activity }
        else { sceneActivities.removeValue(forKey: activity.sceneID) }
        sceneIdle?.receive(activity)
        refreshEffective()
    }

    func refreshEffective() {
        effective = timer.activeOwners.contains(id)
    }

    func configure(_ runtime: MiniAppRuntime) throws {
        let scope = try runtime.makeSceneIdleTimer(for: id, using: timer)
        sceneIdle = scope
        for activity in sceneActivities.values { scope.receive(activity) }
        try scope.setRequested(requested)
        refreshEffective()
    }

    func resetAppearanceReadings() {
        rootEnvironment = "unread"
        rootTrait = "unread"
        sheetEnvironment = "closed"
        sheetTrait = "closed"
    }
}

@MainActor
private final class P2AppearanceRuntimeHolder {
    weak var feature: P2AppearanceFeature?
    func configure(_ runtime: MiniAppRuntime) throws { try feature?.configure(runtime) }
}

enum P2AppearancePolicy {
    case environment(ColorScheme)
    case preferred(ColorScheme)
    case inherited
}

struct P2AppearanceRoot: View {
    @Bindable var feature: P2AppearanceFeature
    let policy: P2AppearancePolicy

    var body: some View {
        applyPolicy(to: NavigationStack {
            Form {
                Section("Appearance") {
                    P2AppearanceReading(label: "root", feature: feature)
                    Button("Sheetを表示") { feature.showingSheet = true }
                        .accessibilityIdentifier("p2.appearance.\(feature.id.rawValue).sheet.open")
                }
                Section("Idle timer") {
                    Toggle("画面を点灯し続ける", isOn: Binding(
                        get: { feature.requested }, set: { value in feature.setRequested(value) }
                    ))
                    Text("requested=\(feature.requested) effective=\(feature.effective)")
                        .accessibilityIdentifier("p2.appearance.\(feature.id.rawValue).idle")
                    Button("状態を再読込") { feature.refreshEffective() }
                }
            }
            .navigationTitle(feature.title)
            .sheet(isPresented: $feature.showingSheet) {
                P2AppearanceReading(label: "sheet", feature: feature)
            }
        })
    }

    @ViewBuilder
    private func applyPolicy<Content: View>(to content: Content) -> some View {
        switch policy {
        case .environment(let scheme): content.environment(\.colorScheme, scheme)
        case .preferred(let scheme): content.preferredColorScheme(scheme)
        case .inherited: content
        }
    }
}

private struct P2AppearanceReading: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let feature: P2AppearanceFeature

    var body: some View {
        VStack(alignment: .leading) {
            Text("environment=\(name(colorScheme))")
            Text("trait=\(label == "root" ? feature.rootTrait : feature.sheetTrait)")
        }
        .accessibilityIdentifier("p2.appearance.\(feature.id.rawValue).\(label)")
        .background(P2AppearanceTraitReader(
            feature: feature, label: label, environment: name(colorScheme)
        ))
    }

    private func name(_ value: ColorScheme) -> String { value == .dark ? "dark" : "light" }
    private func name(_ value: UIUserInterfaceStyle) -> String {
        switch value { case .dark: "dark"; case .light: "light"; default: "unspecified" }
    }
}

private struct P2AppearanceTraitReader: UIViewControllerRepresentable {
    let feature: P2AppearanceFeature
    let label: String
    let environment: String

    func makeCoordinator() -> Coordinator { Coordinator(feature: feature, label: label) }

    func makeUIViewController(context: Context) -> P2AppearanceTraitViewController {
        P2AppearanceTraitViewController { [weak coordinator = context.coordinator] style in
            coordinator?.submit(style: style)
        }
    }

    func updateUIViewController(_ controller: P2AppearanceTraitViewController, context: Context) {
        context.coordinator.update(feature: feature, label: label, environment: environment)
        controller.report()
    }

    @MainActor
    final class Coordinator {
        private weak var feature: P2AppearanceFeature?
        private var label: String
        private var environment = "unread"
        private var generation = 0

        init(feature: P2AppearanceFeature, label: String) {
            self.feature = feature
            self.label = label
        }

        func update(feature: P2AppearanceFeature, label: String, environment: String) {
            self.feature = feature
            self.label = label
            self.environment = environment
        }

        func submit(style: UIUserInterfaceStyle) {
            generation += 1
            let submitted = generation
            let trait = P2AppearanceTraitReader.name(style)
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, self.generation == submitted, let feature = self.feature else { return }
                if self.label == "root" {
                    if feature.rootEnvironment != self.environment { feature.rootEnvironment = self.environment }
                    if feature.rootTrait != trait { feature.rootTrait = trait }
                } else {
                    if feature.sheetEnvironment != self.environment { feature.sheetEnvironment = self.environment }
                    if feature.sheetTrait != trait { feature.sheetTrait = trait }
                }
            }
        }
    }

    private static func name(_ value: UIUserInterfaceStyle) -> String {
        switch value { case .dark: "dark"; case .light: "light"; default: "unspecified" }
    }
}

@MainActor
final class P2AppearanceTraitViewController: UIViewController {
    var receive: @MainActor (UIUserInterfaceStyle) -> Void
    init(receive: @escaping @MainActor (UIUserInterfaceStyle) -> Void) {
        self.receive = receive
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); report() }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection); report()
    }
    func report() { receive(traitCollection.userInterfaceStyle) }
}

@MainActor
final class P2ContainedAppearanceViewController: UIViewController {
    init(style: UIUserInterfaceStyle) {
        super.init(nibName: nil, bundle: nil)
        overrideUserInterfaceStyle = style
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor @Observable
final class P2AppearanceSelection {
    enum Selected { case first, second }
    var selected: Selected = .first
}

struct P2AppearanceSwitchingRoot: View {
    @Bindable var selection: P2AppearanceSelection
    let first: P2AppearanceFeature
    let second: P2AppearanceFeature

    var body: some View {
        Group {
            switch selection.selected {
            case .first: P2AppearanceRoot(feature: first, policy: .environment(.dark))
            case .second: P2AppearanceRoot(feature: second, policy: .preferred(.light))
            }
        }
    }
}
#endif

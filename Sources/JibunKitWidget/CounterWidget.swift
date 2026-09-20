#if os(iOS)
import CounterFeature
import Foundation
import JibunKitCore
import SwiftUI
import WidgetKit

@main
struct JibunKitWidgetBundle: WidgetBundle {
    var body: some Widget {
        CounterWidget()
    }
}

struct CounterWidget: Widget {
    static let kind = "JibunKitCounterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: CounterProvider()) { entry in
            VStack(spacing: 4) {
                Text(verbatim: CounterWidgetCopy.string(.title))
                    .font(.caption)
                if let status = entry.status, status != .enabled {
                    Text(verbatim: CounterWidgetCopy.status(status))
                        .font(.caption)
                } else if let value = entry.value {
                    Text(value, format: .number)
                        .font(.title)
                        .monospacedDigit()
                } else {
                    Text(verbatim: CounterWidgetCopy.string(.unavailable))
                        .font(.caption)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(MiniAppLink.url(for: MiniAppID("counter")))
        }
        .configurationDisplayName(LocalizedStringKey(CounterWidgetCopy.string(.galleryName)))
        .description(LocalizedStringKey(CounterWidgetCopy.string(.galleryDescription)))
    }
}

/// `Bundle.main` is the Widget extension bundle while this code executes in
/// WidgetKit. Tests must inspect the built `.appex`; substituting a test bundle
/// here would not verify the resources shipped with the extension.
enum CounterWidgetCopy {
    enum Key: String, CaseIterable {
        case title = "counter.title"
        case removed = "counter.status.removed"
        case disabled = "counter.status.disabled"
        case stopped = "counter.status.stopped"
        case unavailable = "counter.status.unavailable"
        case galleryName = "counter.gallery.name"
        case galleryDescription = "counter.gallery.description"
    }

    static func string(_ key: Key) -> String {
        Bundle.main.localizedString(forKey: key.rawValue, value: nil, table: nil)
    }

    static func status(_ status: MiniAppManagement.Status) -> String {
        switch status {
        case .removed: string(.removed)
        case .disabled: string(.disabled)
        case .enabled, .disabling, .removing: string(.stopped)
        }
    }
}

private struct CounterEntry: TimelineEntry {
    let date: Date
    let value: Int?
    var status: MiniAppManagement.Status? = nil
}

private struct CounterProvider: TimelineProvider {
    func placeholder(in context: Context) -> CounterEntry {
        CounterEntry(date: .now, value: 0)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping @Sendable (CounterEntry) -> Void
    ) {
        Task {
            completion(await entry())
        }
    }

    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<CounterEntry>) -> Void
    ) {
        Task {
            let currentEntry = await entry()
            completion(Timeline(
                entries: [currentEntry],
                policy: .after(.now.addingTimeInterval(15 * 60))
            ))
        }
    }

    private func entry() async -> CounterEntry {
        guard let defaults = try? MiniAppStorage.sharedDefaults() else {
            return CounterEntry(date: .now, value: nil)
        }
        let status = MiniAppManagement.savedStatus(for: .counter, defaults: defaults)
        guard status == .enabled else { return CounterEntry(date: .now, value: nil, status: status) }
        let value = try? await CounterStore.shared.currentValue()
        return CounterEntry(date: .now, value: value, status: status)
    }
}
#endif

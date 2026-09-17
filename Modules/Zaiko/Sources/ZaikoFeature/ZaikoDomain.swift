import Foundation

enum ZaikoError: LocalizedError {
    case validation(String)
    case itemNotFound
    case importFailed

    var errorDescription: String? {
        switch self {
        case .validation(let message):
            return message
        case .itemNotFound:
            return "対象の在庫が見つかりませんでした。"
        case .importFailed:
            return "JSONバックアップを読み込めませんでした。"
        }
    }
}

enum DisplayMode: String, Codable, CaseIterable {
    case perUnitTime = "per-unit-time"
    case perDayAmount = "per-day-amount"

    func speedLabel(for unit: String) -> String {
        let suffix = unit.trimmed.isEmpty ? "単位" : unit.trimmed
        switch self {
        case .perDayAmount:
            return "1日あたりの使用量"
        case .perUnitTime:
            return "1\(suffix)あたりの使用日数"
        }
    }

    func helpText(for unit: String) -> String {
        let suffix = unit.trimmed.isEmpty ? "単位" : unit.trimmed
        switch self {
        case .perDayAmount:
            return "\(suffix)を1日でどれくらい使うかを入力します。"
        case .perUnitTime:
            return "1\(suffix)が何日くらい持つかを入力します。"
        }
    }

    var placeholderText: String {
        switch self {
        case .perDayAmount:
            return "例: 12"
        case .perUnitTime:
            return "例: 3"
        }
    }
}

struct GlobalPauseState: Codable {
    var active: Bool
    var startedAt: Date?
}

struct AppState: Codable {
    var globalPause: GlobalPauseState
    var unitPreferences: [String: DisplayMode]
    var installMarker: String
    var firstSavedAt: Date?
    var alertThresholdDays: Double
    var notificationsEnabled: Bool
    var notificationRecords: [String: String]

    private enum CodingKeys: String, CodingKey {
        case globalPause
        case unitPreferences
        case installMarker
        case firstSavedAt
        case alertThresholdDays
        case notificationsEnabled
        case notificationRecords
    }

    static func makeDefault() -> AppState {
        AppState(
            globalPause: GlobalPauseState(active: false, startedAt: nil),
            unitPreferences: InventoryDomain.defaultUnitPreferences,
            installMarker: UUID().uuidString,
            firstSavedAt: nil,
            alertThresholdDays: InventoryDomain.defaultAlertThresholdDays,
            notificationsEnabled: true,
            notificationRecords: [:]
        )
    }

    init(
        globalPause: GlobalPauseState,
        unitPreferences: [String: DisplayMode],
        installMarker: String,
        firstSavedAt: Date?,
        alertThresholdDays: Double,
        notificationsEnabled: Bool,
        notificationRecords: [String: String]
    ) {
        self.globalPause = globalPause
        self.unitPreferences = unitPreferences
        self.installMarker = installMarker
        self.firstSavedAt = firstSavedAt
        self.alertThresholdDays = alertThresholdDays
        self.notificationsEnabled = notificationsEnabled
        self.notificationRecords = notificationRecords
    }

    func mergedWithDefaults() -> AppState {
        var next = self
        next.unitPreferences = InventoryDomain.defaultUnitPreferences.merging(unitPreferences) { _, new in new }
        if next.installMarker.isEmpty {
            next.installMarker = UUID().uuidString
        }
        if next.alertThresholdDays <= 0 {
            next.alertThresholdDays = InventoryDomain.defaultAlertThresholdDays
        }
        return next
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        globalPause = try container.decodeIfPresent(GlobalPauseState.self, forKey: .globalPause)
            ?? GlobalPauseState(active: false, startedAt: nil)
        unitPreferences = try container.decodeIfPresent([String: DisplayMode].self, forKey: .unitPreferences) ?? [:]
        installMarker = try container.decodeIfPresent(String.self, forKey: .installMarker) ?? ""
        firstSavedAt = try container.decodeIfPresent(Date.self, forKey: .firstSavedAt)
        alertThresholdDays = try container.decodeIfPresent(Double.self, forKey: .alertThresholdDays)
            ?? InventoryDomain.defaultAlertThresholdDays
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        notificationRecords = try container.decodeIfPresent([String: String].self, forKey: .notificationRecords) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(globalPause, forKey: .globalPause)
        try container.encode(unitPreferences, forKey: .unitPreferences)
        try container.encode(installMarker, forKey: .installMarker)
        try container.encodeIfPresent(firstSavedAt, forKey: .firstSavedAt)
        try container.encode(alertThresholdDays, forKey: .alertThresholdDays)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(notificationRecords, forKey: .notificationRecords)
    }
}

struct InventoryItem: Codable, Identifiable, Hashable {
    var id: Int64
    var name: String
    var category: String
    var unit: String
    var lastPurchased: Date
    var currentStock: Double
    var consumptionRatePerDay: Double?
    var count: Int
    var needsConsumptionSetup: Bool

    var notificationCycleKey: String {
        let stock = String(format: "%.4f", currentStock)
        let rate = String(format: "%.6f", consumptionRatePerDay ?? 0)
        return "\(id)|\(lastPurchased.timeIntervalSince1970)|\(stock)|\(rate)"
    }

    func speedSummary(mode: DisplayMode) -> String? {
        guard let consumptionRatePerDay, consumptionRatePerDay > 0, !needsConsumptionSetup else {
            return nil
        }

        let displayUnit = unit.trimmed.isEmpty ? "単位" : unit.trimmed
        switch mode {
        case .perDayAmount:
            return "約 \(consumptionRatePerDay.formattedNumber(maximumFractionDigits: 2)) \(displayUnit)/日"
        case .perUnitTime:
            let daysPerUnit = 1 / consumptionRatePerDay
            return "約 \(daysPerUnit.formattedNumber(maximumFractionDigits: 2)) 日/\(displayUnit)"
        }
    }
}

struct BackupEnvelope: Codable {
    var version: Int
    var items: [InventoryItem]
    var app: AppState
}

struct LegacyBackupEnvelope: Decodable {
    var version: Int?
    var items: [LegacyInventoryItem]
    var app: LegacyAppState?
}

struct LegacyAppState: Decodable {
    var globalPause: GlobalPauseState?
    var unitPreferences: [String: DisplayMode]?
    var installMarker: String?
    var firstSavedAt: Date?
    var alertThresholdDays: Double?
}

struct LegacyInventoryItem: Decodable {
    var id: Double?
    var name: String?
    var category: String?
    var unit: String?
    var lastPurchased: String?
    var currentStock: Double?
    var lastStock: Double?
    var consumptionRatePerDay: Double?
    var consumptionPace: Double?
    var cycle: Double?
    var count: Int?
    var needsConsumptionSetup: Bool?
}

struct ItemDraft {
    var name: String
    var category: String
    var unit: String
    var stock: String
    var speed: String
    var displayMode: DisplayMode

    init(
        name: String,
        category: String,
        unit: String,
        stock: String,
        speed: String,
        displayMode: DisplayMode
    ) {
        self.name = name
        self.category = category
        self.unit = unit
        self.stock = stock
        self.speed = speed
        self.displayMode = displayMode
    }

    static func empty() -> ItemDraft {
        ItemDraft(
            name: "",
            category: "",
            unit: "",
            stock: "",
            speed: "",
            displayMode: .perUnitTime
        )
    }

    init(item: InventoryItem, mode: DisplayMode, pauseState: GlobalPauseState, now: Date = .now) {
        name = item.name
        category = item.category == InventoryDomain.defaultCategory ? "" : item.category
        unit = item.unit
        stock = InventoryDomain.remainingStock(for: item, pauseState: pauseState, now: now)
            .map { max(0, $0).formValue(maximumFractionDigits: 4) } ?? ""
        speed = InventoryDomain.speedToFormValue(rate: item.consumptionRatePerDay, mode: mode)
        displayMode = mode
    }

    func validate() throws {
        let trimmedName = name.trimmed
        guard !trimmedName.isEmpty else {
            throw ZaikoError.validation("名前を入力してください。")
        }

        _ = try InventoryDomain.parseNonNegativeNumber(stock, fieldName: "在庫量")
        _ = try InventoryDomain.parsePositiveNumber(speed, fieldName: displayMode.speedLabel(for: unit))
    }
}

enum InventoryDomain {
    static let defaultCategory = "未分類"
    static let allCategories = "all"
    static let defaultAlertThresholdDays = 7.0
    static let alpha = 0.3

    static let defaultUnitPreferences: [String: DisplayMode] = [
        "個": .perUnitTime,
        "本": .perUnitTime,
        "枚": .perUnitTime,
        "箱": .perUnitTime,
        "巻": .perUnitTime,
        "パック": .perUnitTime,
        "袋": .perUnitTime,
        "粒": .perUnitTime,
        "錠": .perUnitTime,
        "回": .perUnitTime,
        "セット": .perUnitTime,
        "ml": .perDayAmount,
        "mL": .perDayAmount,
        "l": .perDayAmount,
        "L": .perDayAmount,
        "g": .perDayAmount,
        "kg": .perDayAmount
    ]

    static func parseNumber(_ rawValue: String, fieldName: String) throws -> Double {
        guard let value = Double(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.isFinite else {
            throw ZaikoError.validation("\(fieldName)は数値で入力してください。")
        }
        return value
    }

    static func parseNonNegativeNumber(_ rawValue: String, fieldName: String) throws -> Double {
        let value = try parseNumber(rawValue, fieldName: fieldName)
        guard value >= 0 else {
            throw ZaikoError.validation("\(fieldName)は0以上で入力してください。")
        }
        return value
    }

    static func parsePositiveNumber(_ rawValue: String, fieldName: String) throws -> Double {
        let value = try parseNumber(rawValue, fieldName: fieldName)
        guard value > 0 else {
            throw ZaikoError.validation("\(fieldName)は0より大きい数値で入力してください。")
        }
        return value
    }

    static func displayMode(for item: InventoryItem, appState: AppState) -> DisplayMode {
        if let mode = appState.unitPreferences[item.unit.trimmed], !item.unit.trimmed.isEmpty {
            return mode
        }
        return inferDisplayMode(for: item.unit)
    }

    static func inferDisplayMode(for unit: String) -> DisplayMode {
        defaultUnitPreferences[unit.trimmed] ?? .perUnitTime
    }

    static func consumptionRate(from speedValue: String, mode: DisplayMode) throws -> Double {
        let speed = try parsePositiveNumber(speedValue, fieldName: mode.speedLabel(for: ""))
        switch mode {
        case .perDayAmount:
            return speed
        case .perUnitTime:
            let rate = 1 / speed
            guard rate.isFinite, rate > 0 else {
                throw ZaikoError.validation("消費速度が扱える数値の範囲を超えています。")
            }
            return rate
        }
    }

    static func speedToFormValue(rate: Double?, mode: DisplayMode) -> String {
        guard let rate, rate > 0 else {
            return ""
        }

        switch mode {
        case .perDayAmount:
            return rate.formValue(maximumFractionDigits: 4)
        case .perUnitTime:
            return (1 / rate).formValue(maximumFractionDigits: 4)
        }
    }

    static func makeItem(from draft: ItemDraft, now: Date = .now) throws -> InventoryItem {
        try draft.validate()
        let rate = try consumptionRate(from: draft.speed, mode: draft.displayMode)
        return InventoryItem(
            id: Int64(Date().timeIntervalSince1970 * 1000),
            name: draft.name.trimmed,
            category: draft.category.trimmed.isEmpty ? defaultCategory : draft.category.trimmed,
            unit: draft.unit.trimmed,
            lastPurchased: now,
            currentStock: try parseNonNegativeNumber(draft.stock, fieldName: "在庫量"),
            consumptionRatePerDay: rate,
            count: 1,
            needsConsumptionSetup: false
        )
    }

    static func updateItem(_ item: InventoryItem, with draft: ItemDraft, now: Date = .now) throws -> InventoryItem {
        try draft.validate()
        let rate = try consumptionRate(from: draft.speed, mode: draft.displayMode)
        return InventoryItem(
            id: item.id,
            name: draft.name.trimmed,
            category: draft.category.trimmed.isEmpty ? defaultCategory : draft.category.trimmed,
            unit: draft.unit.trimmed,
            lastPurchased: now,
            currentStock: try parseNonNegativeNumber(draft.stock, fieldName: "在庫量"),
            consumptionRatePerDay: rate,
            count: item.count,
            needsConsumptionSetup: false
        )
    }

    static func elapsedDays(for item: InventoryItem, pauseState: GlobalPauseState, now: Date = .now) -> Double {
        let effectiveNow = pauseState.active ? (pauseState.startedAt ?? now) : now
        return max(0, effectiveNow.timeIntervalSince(item.lastPurchased) / 86_400)
    }

    static func remainingStock(for item: InventoryItem, pauseState: GlobalPauseState, now: Date = .now) -> Double? {
        guard
            item.currentStock >= 0,
            let rate = item.consumptionRatePerDay,
            rate > 0,
            !item.needsConsumptionSetup
        else {
            return nil
        }

        let consumed = rate * elapsedDays(for: item, pauseState: pauseState, now: now)
        return item.currentStock - consumed
    }

    static func remainingDays(for item: InventoryItem, pauseState: GlobalPauseState, now: Date = .now) -> Double? {
        guard
            let rate = item.consumptionRatePerDay,
            rate > 0,
            let remainingStock = remainingStock(for: item, pauseState: pauseState, now: now)
        else {
            return nil
        }

        return remainingStock / rate
    }

    static func isAlert(
        item: InventoryItem,
        pauseState: GlobalPauseState,
        thresholdDays: Double,
        now: Date = .now
    ) -> Bool {
        guard let remaining = remainingDays(for: item, pauseState: pauseState, now: now) else {
            return false
        }
        return remaining <= thresholdDays
    }

    static func sortedItems(
        _ items: [InventoryItem],
        pauseState: GlobalPauseState,
        thresholdDays: Double,
        now: Date = .now
    ) -> [InventoryItem] {
        items.sorted { lhs, rhs in
            let lhsRemaining = remainingDays(for: lhs, pauseState: pauseState, now: now)
            let rhsRemaining = remainingDays(for: rhs, pauseState: pauseState, now: now)

            switch (lhsRemaining, rhsRemaining) {
            case let (lhsValue?, rhsValue?):
                let lhsAlert = lhsValue <= thresholdDays
                let rhsAlert = rhsValue <= thresholdDays
                if lhsAlert != rhsAlert {
                    return lhsAlert
                }
                return lhsValue < rhsValue
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }
        }
    }

    static func applyRestock(
        to item: InventoryItem,
        remaining: Double,
        added: Double,
        pauseState: GlobalPauseState,
        now: Date = .now
    ) -> InventoryItem {
        let elapsed = elapsedDays(for: item, pauseState: pauseState, now: now)
        var nextRate = item.consumptionRatePerDay

        if item.currentStock >= remaining, elapsed > 0.5 {
            let consumed = max(0, item.currentStock - remaining)
            let measuredRate = consumed / elapsed
            if measuredRate > 0 {
                if let currentRate = nextRate {
                    nextRate = (alpha * measuredRate) + ((1 - alpha) * currentRate)
                } else {
                    nextRate = measuredRate
                }
            }
        }

        return InventoryItem(
            id: item.id,
            name: item.name,
            category: item.category,
            unit: item.unit,
            lastPurchased: now,
            currentStock: remaining + added,
            consumptionRatePerDay: nextRate,
            count: max(1, item.count + 1),
            needsConsumptionSetup: false
        )
    }

    static func shiftItemsForPause(_ items: [InventoryItem], pauseStartedAt: Date?, resumedAt: Date = .now) -> [InventoryItem] {
        guard let pauseStartedAt else {
            return items
        }

        let duration = resumedAt.timeIntervalSince(pauseStartedAt)
        guard duration > 0 else {
            return items
        }

        return items.map { item in
            guard item.lastPurchased < resumedAt else {
                return item
            }

            let pausedDuration = resumedAt.timeIntervalSince(max(pauseStartedAt, item.lastPurchased))
            var shifted = item
            shifted.lastPurchased = item.lastPurchased.addingTimeInterval(pausedDuration)
            return shifted
        }
    }

    static func recordsAfterCancellingPending(
        _ records: [String: String],
        pendingIDs: Set<String>,
        requestIdentifier: (String) -> String
    ) -> [String: String] {
        records.filter { !pendingIDs.contains(requestIdentifier($0.key)) }
    }

    static func recordsAfterPauseShift(
        _ records: [String: String],
        before: [InventoryItem],
        after: [InventoryItem]
    ) -> [String: String] {
        var updated = records
        for (old, shifted) in zip(before, after) where old.id == shifted.id {
            if records[String(old.id)] == old.notificationCycleKey {
                updated[String(old.id)] = shifted.notificationCycleKey
            }
        }
        return updated
    }

    /// A recorded cycle stays handled after delivery, even if the user clears
    /// Notification Center. Explicitly cancelled pending requests have their
    /// records removed by the Store and can be scheduled again.
    static func shouldSkipReschedule(
        hasRecord: Bool,
        fireDate: Date,
        now: Date = .now
    ) -> Bool {
        hasRecord && fireDate <= now.addingTimeInterval(6)
    }

    static func normalize(_ legacyItem: LegacyInventoryItem, now: Date = .now) -> InventoryItem? {
        guard let rawName = legacyItem.name?.trimmed, !rawName.isEmpty else {
            return nil
        }

        let stock = legacyItem.currentStock ?? legacyItem.lastStock ?? 0
        let rate = legacyItem.consumptionRatePerDay
            ?? legacyItem.consumptionPace
            ?? {
                guard let cycle = legacyItem.cycle, cycle > 0 else {
                    return nil
                }
                return stock / cycle
            }()

        let fallbackDate = now
        let lastPurchased = DateCoding.date(from: legacyItem.lastPurchased ?? "") ?? fallbackDate

        return InventoryItem(
            id: Int64(legacyItem.id ?? Double(Int64(Date().timeIntervalSince1970 * 1000))),
            name: rawName,
            category: legacyItem.category?.trimmed.isEmpty == false ? legacyItem.category!.trimmed : defaultCategory,
            unit: legacyItem.unit?.trimmed ?? "",
            lastPurchased: lastPurchased,
            currentStock: max(0, stock),
            consumptionRatePerDay: rate,
            count: max(legacyItem.count ?? 1, 1),
            needsConsumptionSetup: legacyItem.needsConsumptionSetup ?? (rate == nil)
        )
    }
}

enum DateCoding {
    static func date(from rawValue: String) -> Date? {
        formatter(options: [.withInternetDateTime, .withFractionalSeconds]).date(from: rawValue)
            ?? formatter(options: [.withInternetDateTime]).date(from: rawValue)
    }

    static func string(from date: Date) -> String {
        formatter(options: [.withInternetDateTime, .withFractionalSeconds]).string(from: date)
    }

    private static func formatter(options: ISO8601DateFormatter.Options) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = options
        return formatter
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Double {
    var formattedNumber: String {
        formattedNumber(maximumFractionDigits: 2)
    }

    func formattedNumber(maximumFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: self)) ?? String(self)
    }

    /// Plain form value without grouping separators, mirroring the web
    /// `String(Number(value.toFixed(n)))` so parsed input round-trips.
    func formValue(maximumFractionDigits: Int) -> String {
        let factor = pow(10.0, Double(maximumFractionDigits))
        let rounded = (self * factor).rounded() / factor
        if rounded.truncatingRemainder(dividingBy: 1) == 0, abs(rounded) < 1e15 {
            return String(Int64(rounded))
        }
        return String(rounded)
    }
}

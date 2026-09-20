#if os(iOS)
import SwiftUI
import JibunKitCore

@MainActor
enum P2BluetoothProbe {
    static let diagnostics = P2BluetoothDiagnosticLog(defaults: UserDefaults(suiteName: "com.jibunkit.p2-bluetooth-diagnostics") ?? .standard)
    static let coordinator = MiniAppBluetoothCoordinator { owner, restorationIdentifier in
        MiniAppCoreBluetoothCentral(owner: owner, restorationIdentifier: restorationIdentifier,
            diagnostics: { message in diagnostics.appendNative(owner: owner, message: message) })
    }
    static let sensor = P2BluetoothFeature(id: MiniAppID("p2-bluetooth-sensor"), title: "BLE Sensor",
        coordinator: coordinator, diagnostics: diagnostics)
    static let accessory = P2BluetoothFeature(id: MiniAppID("p2-bluetooth-accessory"), title: "BLE Accessory",
        coordinator: coordinator, diagnostics: diagnostics)
    static var definitions: [MiniAppDefinition] { [sensor.definition, accessory.definition] }
}

@MainActor
final class P2BluetoothDiagnosticLog: ObservableObject {
    // consumerConnect is retained only so v2 persisted entries remain decodable; it never qualifies success.
    enum Kind: String, Codable { case processStart, native, hostLaunch, ownerOnRestore, consumerConnect,
        consumerConnectBegin, consumerConnectCompleted, consumerConnectFailed, restoredConnected, restoredNotification }
    private struct Entry: Codable {
        let time: Date, processID: UUID, owner: String?, kind: Kind, message: String, generation: UUID?
    }
    private static let entriesKey = "entries.v2", processKey = "latest-process.v2", maximumEntries = 120
    let processID: UUID
    let previousProcessID: UUID?
    @Published private(set) var lines: [String] = []
    @Published private(set) var coldRestoreStatus = "このprocessではOS復元callback由来のconnectedを確認していません"
    @Published private(set) var latestCompletedRestoreEvidence = "過去processの完全な復元通知証拠: なし"
    private let defaults: UserDefaults, now: @MainActor () -> Date
    private var entries: [Entry]
    private var volatileLines: [String] = []

    init(defaults: UserDefaults = .standard, processID: UUID = UUID(), systemPID: Int32 = ProcessInfo.processInfo.processIdentifier,
         now: @escaping @MainActor () -> Date = { Date.now }) {
        self.defaults = defaults; self.processID = processID; self.now = now
        previousProcessID = defaults.string(forKey: Self.processKey).flatMap(UUID.init(uuidString:))
        let decoded = (defaults.data(forKey: Self.entriesKey)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        entries = decoded.suffix(Self.maximumEntries).map {
            Entry(time: $0.time, processID: $0.processID, owner: $0.owner, kind: $0.kind,
                  message: String($0.message.prefix(512)), generation: $0.generation)
        }
        defaults.set(processID.uuidString, forKey: Self.processKey)
        append(kind: .processStart, owner: nil,
               message: "process-start systemPID=\(systemPID) previous=\(previousProcessID?.uuidString ?? "none")")
    }

    func appendNative(owner: MiniAppID, message: String) {
        if message.hasPrefix("willRestoreState ") {
            append(kind: .native, owner: owner, message: message)
        } else {
            volatileLines.append(format(time: now(), processID: processID, owner: owner.rawValue,
                                        kind: .native, message: String(message.prefix(512))))
            if volatileLines.count > 80 { volatileLines.removeFirst(volatileLines.count - 80) }
            rebuildPresentation()
        }
    }
    func record(_ kind: Kind, owner: MiniAppID, generation: UUID? = nil, message: String) {
        append(kind: kind, owner: owner, generation: generation, message: message)
    }
    private func append(kind: Kind, owner: MiniAppID?, generation: UUID? = nil, message: String) {
        let bounded = String(message.prefix(512))
        entries.append(.init(time: now(), processID: processID, owner: owner?.rawValue, kind: kind,
                             message: bounded, generation: generation))
        if entries.count > Self.maximumEntries { entries.removeFirst(entries.count - Self.maximumEntries) }
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: Self.entriesKey) }
        rebuildPresentation()
    }
    private func rebuildPresentation() {
        lines = entries.map { format(time: $0.time, processID: $0.processID, owner: $0.owner,
                                     kind: $0.kind, message: $0.message) } + volatileLines
        let current = entries.filter { $0.processID == processID }
        rebuildHistoricalEvidence()
        guard let previousProcessID, previousProcessID != processID else {
            coldRestoreStatus = "このprocessではOS復元callback由来のconnectedを確認していません"
            return
        }
        let restored = qualifiedRestoredConnections(in: current)
        guard !restored.isEmpty else {
            coldRestoreStatus = "このprocessではOS復元callback由来のconnectedを確認していません"
            return
        }
        let qualification = "新processでOS復元callbackからconnectedを確認（OSの起動契機は未判定）"
        if restored.contains(where: { connected in current.contains(where: {
            $0.kind == .restoredNotification && $0.owner == connected.owner
                && $0.generation == connected.generation
        }) }) {
            coldRestoreStatus = "新processでOS復元callbackと同一世代の初回通知を確認（OSの起動契機は未判定）"
        } else {
            coldRestoreStatus = qualification
        }
    }
    private func qualifiedRestoredConnections(in processEntries: [Entry]) -> [Entry] {
        processEntries.filter { connected in
            guard connected.kind == .restoredConnected, let owner = connected.owner,
                  connected.generation != nil else { return false }
            return processEntries.contains { $0.kind == .native && $0.owner == owner && $0.message.hasPrefix("willRestoreState ") }
                && processEntries.contains { $0.kind == .ownerOnRestore && $0.owner == owner }
                && processEntries.contains { $0.kind == .consumerConnectCompleted && $0.owner == owner }
        }
    }
    private func rebuildHistoricalEvidence() {
        var latest: (connected: Entry, notification: Entry)?
        for (historicalProcess, processEntries) in Dictionary(grouping: entries.filter { $0.processID != processID },
                                                               by: \.processID) {
            guard processEntries.contains(where: {
                $0.kind == .processStart && !$0.message.hasSuffix("previous=none")
            }) else { continue }
            for connected in qualifiedRestoredConnections(in: processEntries) {
                guard let notification = processEntries.filter({
                    $0.processID == historicalProcess && $0.kind == .restoredNotification
                        && $0.owner == connected.owner && $0.generation == connected.generation
                }).max(by: { $0.time < $1.time }) else { continue }
                if latest == nil || latest!.notification.time < notification.time {
                    latest = (connected, notification)
                }
            }
        }
        guard let latest, let owner = latest.connected.owner, let generation = latest.connected.generation else {
            latestCompletedRestoreEvidence = "過去processの完全な復元通知証拠: なし"
            return
        }
        latestCompletedRestoreEvidence = "過去processの完全な復元通知証拠: \(latest.notification.time.ISO8601Format()) "
            + "process=\(latest.notification.processID.uuidString) owner=\(owner) generation=\(generation.uuidString)"
    }
    private func format(time: Date, processID: UUID, owner: String?, kind: Kind, message: String) -> String {
        let owner = owner.map { " [\($0)]" } ?? ""
        return "\(time.ISO8601Format()) [process=\(processID.uuidString)]\(owner) [\(kind.rawValue)] \(message)"
    }
    var text: String { lines.joined(separator: "\n") }
}

private struct P2BluetoothDiagnosticLogView: View {
    @ObservedObject var log: P2BluetoothDiagnosticLog
    var body: some View {
        Section("BLE接続記録（両Feature）") {
            Text(log.coldRestoreStatus).accessibilityIdentifier("p2.bluetooth.cold-restore-status")
            Text(log.latestCompletedRestoreEvidence)
                .accessibilityIdentifier("p2.bluetooth.latest-completed-restore-evidence")
            ShareLink("診断記録を共有", item: log.text)
            Text(log.text.isEmpty ? "記録なし" : log.text)
                .font(.caption.monospaced()).textSelection(.enabled)
        }
    }
}

enum P2BluetoothDiagnosticInput {
    static func normalizedUUID(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let uuid = UUID(uuidString: value) { return uuid.uuidString }
        guard [4, 8, 32].contains(value.count),
              value.allSatisfy({ "0123456789abcdefABCDEF".contains($0) }) else { return nil }
        if value.count == 32 {
            let digits = Array(value.uppercased())
            return [0..<8, 8..<12, 12..<16, 16..<20, 20..<32]
                .map { String(digits[$0]) }.joined(separator: "-")
        }
        return value.uppercased()
    }

    static func data(hex input: String) -> Data? {
        let value = input.filter { !$0.isWhitespace }
        guard !value.isEmpty, value.count.isMultiple(of: 2), value.allSatisfy({ $0.isHexDigit }) else { return nil }
        var data = Data(), index = value.startIndex
        while index < value.endIndex {
            let end = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<end], radix: 16) else { return nil }
            data.append(byte); index = end
        }
        return data
    }

    static func hex(_ data: Data) -> String { data.map { String(format: "%02X", $0) }.joined(separator: " ") }
}

@MainActor
final class P2BluetoothFeature: ObservableObject {
    let id: MiniAppID, title: String
    let service: MiniAppBluetoothService
    let consents: MiniAppConsentStore
    let lifetime: MiniAppFeatureLifetime
    @Published var status = "停止中"
    @Published var peripherals: [MiniAppBluetoothPeripheral] = []
    @Published private(set) var connection: MiniAppBluetoothConnection?
    @Published var serviceUUID = "180D"
    @Published var characteristicUUID = "2A37"
    @Published var writeHex = "01"
    @Published private(set) var discoveredServices: [String] = []
    @Published private(set) var discoveredCharacteristics: [String] = []
    @Published private(set) var lastReadHex = "未受信"
    @Published private(set) var lastNotifyHex = "未受信"
    @Published private(set) var writeResult = "未送信"
    @Published private(set) var notifyResult = "未設定"
    private var awaitingRead = false
    private let diagnostics: P2BluetoothDiagnosticLog?
    private var restoredGenerations: Set<UUID> = [], notifiedRestoredGenerations: Set<UUID> = []

    init(id: MiniAppID, title: String, coordinator: MiniAppBluetoothCoordinator = .shared,
         consents: MiniAppConsentStore = MiniAppConsentStore(defaults: .standard),
         diagnostics: P2BluetoothDiagnosticLog? = nil) {
        self.id = id; self.title = title; self.consents = consents; self.diagnostics = diagnostics
        let service = MiniAppBluetoothService(owner: id, coordinator: coordinator)
        self.service = service
        lifetime = MiniAppFeatureLifetime(id: id) { [service, consents, id, diagnostics] runtime in
            guard consents.consent(for: id, permissionID: "bluetooth") == .allowed else {
                throw MiniAppBluetoothFailure.permissionDenied(.notDetermined)
            }
            diagnostics?.record(.consumerConnectBegin, owner: id, message: "consumer-connect begin")
            try await service.connect(to: runtime)
            diagnostics?.record(.consumerConnectCompleted, owner: id, message: "consumer-connect completed")
        }
        service.receive = { [weak self] event in self?.receive(event) }
    }
    var definition: MiniAppDefinition {
        MiniAppDefinition(id: id, title: title, systemImage: "antenna.radiowaves.left.and.right",
            lifetime: lifetime,
            permissions: [.init(id: "bluetooth", title: "Bluetooth", purpose: "近くのBLE機器に接続します", deniedBehavior: "スキャンと接続を開始しません")],
            onConsentChange: { [weak self] permission, decision in
                guard let self, permission == "bluetooth" else { return }
                self.lifetime.setStartAllowed(decision == .allowed)
                if decision != .allowed {
                    Task { await self.lifetime.stop(); await self.service.unregisterAllOwned() }
                }
            },
            onUnregister: { [weak self] in await self?.service.unregisterAllOwned() },
            onHostLaunch: { [weak self] in
                guard let self else { return }
                let admitted = self.lifetime.isStartAllowed && self.consents.consent(for: self.id, permissionID: "bluetooth") == .allowed
                self.diagnostics?.record(.hostLaunch, owner: self.id, message: "onHostLaunch admitted=\(admitted)")
                self.service.prepareRestoration(admitted: admitted) { [weak self] in
                    guard let self else { return }
                    self.diagnostics?.record(.ownerOnRestore, owner: self.id, message: "owner onRestore invoked")
                    Task {
                        do { try await self.lifetime.start() }
                        catch { self.diagnostics?.record(.consumerConnectFailed, owner: self.id, message: "consumer-connect failed type=\(String(reflecting: type(of: error)))") }
                    }
                }
            }
        ) { [self] _ in P2BluetoothView(feature: self) }
    }
    func scan() { report { try service.scan(); status = "スキャン中" } }
    func stopScan() { report { try service.stopScan(); status = "スキャン停止" } }
    func connect(_ peripheral: MiniAppBluetoothPeripheral) { reportAsync { self.connection = try await self.service.connect(peripheral: peripheral.id) } }
    func disconnect() { reportAsync { if let connection = self.connection { try await self.service.disconnect(connection); self.connection = nil } } }
    func selectService(_ value: String) { serviceUUID = value }
    func selectCharacteristic(_ value: String) { characteristicUUID = value }
    func discoverAllServices() { report { guard let connection = requireConnection() else { return }; try service.discoverServices(nil, on: connection) } }
    func discover() {
        guard let serviceID = validUUID(serviceUUID, label: "Service UUID") else { return }
        report { guard let connection = requireConnection() else { return }; try service.discoverServices([serviceID], on: connection) }
    }
    func discoverCharacteristic() {
        guard let key = diagnosticCharacteristic() else { return }
        report { guard let connection = requireConnection() else { return }; try service.discoverCharacteristics([key.characteristic], service: key.service, on: connection) }
    }
    func discoverAllCharacteristics() {
        guard let serviceID = validUUID(serviceUUID, label: "Service UUID") else { return }
        report { guard let connection = requireConnection() else { return }; try service.discoverCharacteristics(nil, service: serviceID, on: connection) }
    }
    func read() {
        guard let key = diagnosticCharacteristic() else { lastReadHex = status; return }
        report { guard let connection = requireConnection() else { return }; awaitingRead = true; try service.read(key, on: connection); status = "Read要求送信済み" }
    }
    func write() {
        guard let key = diagnosticCharacteristic() else { writeResult = status; return }
        guard let data = P2BluetoothDiagnosticInput.data(hex: writeHex) else {
            writeResult = "拒否: 送信bytesは空でない偶数桁のhex（空白区切り可）"; status = writeResult; return
        }
        do {
            guard let connection = requireConnection() else { return }
            writeResult = "応答待ち（\(data.count) bytes）"
            try service.write(data, to: key, type: .withResponse, on: connection)
        } catch { writeResult = "送信拒否/失敗: \(error)"; status = writeResult }
    }
    func subscribe(_ enabled: Bool) {
        guard let key = diagnosticCharacteristic() else { notifyResult = status; return }
        do {
            guard let connection = requireConnection() else { return }
            notifyResult = enabled ? "購読開始応答待ち" : "購読解除応答待ち"
            try service.setNotify(enabled, for: key, on: connection)
        } catch { notifyResult = "Notify拒否/失敗: \(error)"; status = notifyResult }
    }
    private func receive(_ event: MiniAppBluetoothEvent) {
        switch event {
        case .discovered(let peripheral):
            if let index = peripherals.firstIndex(where: { $0.id == peripheral.id }) { peripherals[index] = peripheral }
            else { peripherals.append(peripheral) }
        case .connected(let peripheral, let generation, let restored):
            if restored {
                restoredGenerations.insert(generation)
                diagnostics?.record(.restoredConnected, owner: id, generation: generation,
                    message: "restored-connected delivered peripheral=\(peripheral.uuidString.suffix(8)) generation=\(generation.uuidString.suffix(8))")
                do {
                    if let restoredConnection = try service.currentConnection(peripheral: peripheral) {
                        connection = restoredConnection; status = "復元接続済み（診断操作可能）"
                    } else {
                        status = "復元connected通知を受信したが操作用connection ticketなし"
                    }
                } catch { status = "復元connection取得失敗: \(error)" }
            } else { status = "接続済み" }
        case .disconnected(_, let generation, _):
            restoredGenerations.remove(generation); notifiedRestoredGenerations.remove(generation)
            status = "切断済み"; connection = nil; awaitingRead = false
        case .powerChanged(let power, _): status = "電源: \(power.rawValue)"
        case .services(_, _, let identifiers):
            discoveredServices = Array(Set(identifiers)).sorted(); status = "Service候補 \(identifiers.count)件"
        case .characteristics(_, _, let service, let identifiers):
            discoveredCharacteristics = Array(Set(identifiers)).sorted(); status = "\(service) のCharacteristic候補 \(identifiers.count)件"
        case .value(_, let generation, let characteristic, let data, let notifying):
            let value = P2BluetoothDiagnosticInput.hex(data)
            if awaitingRead { lastReadHex = "\(characteristic.characteristic): \(value)"; awaitingRead = false }
            if notifying {
                lastNotifyHex = "\(characteristic.characteristic): \(value)"
                if restoredGenerations.contains(generation), notifiedRestoredGenerations.insert(generation).inserted {
                    diagnostics?.record(.restoredNotification, owner: id, generation: generation,
                        message: "first restored notification generation=\(generation.uuidString.suffix(8)) characteristic=\(characteristic.characteristic) bytes=\(data.count)")
                }
            }
            status = "値受信 \(data.count) bytes"
        case .writeCompleted(_, _, let characteristic):
            writeResult = "成功: \(characteristic.characteristic)"; status = "Write応答成功"
        case .notificationChanged(_, _, let characteristic, let enabled):
            notifyResult = "\(characteristic.characteristic): \(enabled ? "購読中" : "未購読")"; status = "Notify状態更新"
        case .readyToWriteWithoutResponse(_, _, let maximum): status = "Write without response再開可（最大\(maximum) bytes）"
        case .failed(_, _, let message):
            status = "失敗: \(message)"
            awaitingRead = false
            if writeResult.hasPrefix("応答待ち") { writeResult = "失敗: \(message)" }
            if notifyResult.hasSuffix("応答待ち") { notifyResult = "失敗: \(message)" }
        default: break
        }
    }
    private func validUUID(_ value: String, label: String) -> String? {
        guard let normalized = P2BluetoothDiagnosticInput.normalizedUUID(value) else {
            status = "拒否: \(label)は4/8/32桁hexまたは128-bit UUIDで指定"; return nil
        }
        return normalized
    }
    private func diagnosticCharacteristic() -> MiniAppBluetoothCharacteristic? {
        guard let service = validUUID(serviceUUID, label: "Service UUID"),
              let characteristic = validUUID(characteristicUUID, label: "Characteristic UUID") else { return nil }
        return .init(service: service, characteristic: characteristic)
    }
    private func requireConnection() -> MiniAppBluetoothConnection? {
        guard let connection else { status = "拒否: 操作可能な通常connectionがありません"; return nil }
        return connection
    }
    private func report(_ body: () throws -> Void) { do { try body() } catch { status = "拒否/失敗: \(error)" } }
    private func reportAsync(_ body: @escaping @MainActor () async throws -> Void) {
        Task { do { try await body() } catch { status = "拒否/失敗: \(error)" } }
    }
}

private struct P2BluetoothView: View {
    @ObservedObject var feature: P2BluetoothFeature
    var body: some View {
        Form {
            Text(feature.status).accessibilityIdentifier("p2.bluetooth.\(feature.id.rawValue).status")
            Button("スキャン開始") { feature.scan() }
            Button("スキャン停止") { feature.stopScan() }
            ForEach(feature.peripherals) { peripheral in
                Button(peripheral.name ?? peripheral.id.uuidString) { feature.connect(peripheral) }
            }
            Button("切断") { feature.disconnect() }
            Section("GATT指定") {
                TextField("Service UUID", text: $feature.serviceUUID)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                Button("全Service検索") { feature.discoverAllServices() }
                Button("指定Service検索") { feature.discover() }
                if feature.discoveredServices.isEmpty { Text("Service候補: 未取得") }
                ForEach(feature.discoveredServices, id: \.self) { value in
                    Button("Service候補: \(value)") { feature.selectService(value) }
                }
                TextField("Characteristic UUID", text: $feature.characteristicUUID)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                Button("全Characteristic検索") { feature.discoverAllCharacteristics() }
                Button("指定Characteristic検索") { feature.discoverCharacteristic() }
                if feature.discoveredCharacteristics.isEmpty { Text("Characteristic候補: 未取得") }
                ForEach(feature.discoveredCharacteristics, id: \.self) { value in
                    Button("Characteristic候補: \(value)") { feature.selectCharacteristic(value) }
                }
            }
            Section("値診断") {
                TextField("送信bytes hex（例: 01 FF）", text: $feature.writeHex)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                Button("Read") { feature.read() }
                Button("Write with response") { feature.write() }
                Button("Subscribe") { feature.subscribe(true) }
                Button("Unsubscribe") { feature.subscribe(false) }
                LabeledContent("Read結果", value: feature.lastReadHex)
                LabeledContent("Write結果", value: feature.writeResult)
                LabeledContent("Notify状態", value: feature.notifyResult)
                LabeledContent("Notify受信値", value: feature.lastNotifyHex)
            }
            P2BluetoothDiagnosticLogView(log: P2BluetoothProbe.diagnostics)
        }
    }
}
#endif

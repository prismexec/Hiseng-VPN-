import Foundation
import NetworkExtension
import UIKit

enum VPNState { case off, connecting, reconnecting, disconnecting, on, error }

/// Keeps the key and drives the system VPN profile of the tunnel extension.
@MainActor
final class VPNController: ObservableObject {
    @Published private(set) var state: VPNState = .off
    @Published private(set) var message = ""
    @Published private(set) var errorText: String?
    @Published private(set) var key: String? = UserDefaults.standard.string(forKey: "key")
    @Published private(set) var profile: KeyProfile?
    @Published private(set) var connectedSince: Date?
    @Published private(set) var rx: UInt64 = 0
    @Published private(set) var tx: UInt64 = 0
    @Published private(set) var transport = ""
    @Published var toast: String?

    private var manager: NETunnelProviderManager?
    private var statsTimer: Timer?
    private var toastTask: Task<Void, Never>?
    /// Set once iOS reports this start as connecting: a "disconnected" before
    /// that is the profile being saved, not a failure.
    private var sawConnecting = false

    /// The extension's id follows the app's, so re-signing with another
    /// bundle id keeps them paired.
    private var extensionBundleId: String {
        (Bundle.main.bundleIdentifier ?? "com.hiseng.vpn") + ".tunnel"
    }

    init() {
        if let k = key, case .success(let p) = KeyProfile.decode(k) { profile = p }
        NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        Task { await load() }
    }

    private func load() async {
        let all = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        manager = all.first
        refresh()
    }

    // MARK: key

    @discardableResult
    func saveKey(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = text.range(of: "openflux://[^\\s\"'<>]+", options: .regularExpression) else {
            show("Это не ключ OpenFlux")
            haptic(.error)
            return false
        }
        let k = String(text[range])
        switch KeyProfile.decode(k) {
        case .failure(let f):
            show(f.message)
            haptic(.error)
            return false
        case .success(let p):
            UserDefaults.standard.set(k, forKey: "key")
            key = k
            profile = p
            errorText = nil
            if state == .error { state = .off }
            show("Ключ «\(p.name)» добавлен")
            haptic(.success)
            if isActive { stop() }
            return true
        }
    }

    func pasteKey() {
        guard let s = UIPasteboard.general.string, !s.isEmpty else {
            show("Буфер обмена пуст")
            haptic(.error)
            return
        }
        saveKey(s)
    }

    func deleteKey() {
        if isActive { stop() }
        UserDefaults.standard.removeObject(forKey: "key")
        key = nil
        profile = nil
        show("Ключ удалён")
    }

    // MARK: connection

    var isActive: Bool {
        switch state {
        case .on, .connecting, .reconnecting: return true
        default: return false
        }
    }

    func toggle() {
        haptic(.medium)
        if isActive { stop() } else { start() }
    }

    func start() {
        guard let key = key else {
            show("Сначала добавьте ключ")
            haptic(.error)
            return
        }
        state = .connecting
        message = "Подключаемся…"
        errorText = nil
        sawConnecting = false
        Shared.writeError(nil)
        Task {
            let m = manager ?? NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = extensionBundleId
            proto.serverAddress = profile?.name ?? "Hiseng VPN"
            proto.providerConfiguration = ["link": key]
            proto.disconnectOnSleep = false
            m.protocolConfiguration = proto
            m.localizedDescription = "Hiseng VPN"
            m.isEnabled = true
            do {
                try await m.saveToPreferences()
                try await m.loadFromPreferences()
                manager = m
                try m.connection.startVPNTunnel()
            } catch {
                fail(describeSystem(error))
            }
        }
    }

    func stop() {
        manager?.connection.stopVPNTunnel()
    }

    private func refresh() {
        guard let conn = manager?.connection else { return }
        switch conn.status {
        case .connected:
            state = .on
            message = "Трафик защищён"
            connectedSince = conn.connectedDate ?? Date()
            startStats()
        case .connecting:
            sawConnecting = true
            state = .connecting
            message = "Подключаемся…"
        case .reasserting:
            state = .reconnecting
            message = "Связь потеряна, переподключаемся…"
        case .disconnecting:
            state = .disconnecting
            message = "Отключаемся…"
        case .disconnected, .invalid:
            if state == .connecting && !sawConnecting { return }
            let wasStarting = state == .connecting || state == .reconnecting
            stopStats()
            connectedSince = nil
            if wasStarting {
                collectError(conn)
            } else if state != .error {
                state = .off
                message = ""
            }
        @unknown default:
            state = .off
        }
    }

    /// The tunnel writes its own reason to the app group; iOS itself only
    /// says "internal error".
    private func collectError(_ conn: NEVPNConnection) {
        if let own = Shared.readError() {
            fail(own)
            return
        }
        if #available(iOS 16.0, *) {
            conn.fetchLastDisconnectError { err in
                Task { @MainActor in
                    if let err = err {
                        self.fail(self.describeSystem(err))
                    } else {
                        self.state = .off
                        self.message = ""
                    }
                }
            }
        } else {
            fail("Туннель не запустился. Откройте журнал, чтобы узнать причину.")
        }
    }

    private func fail(_ text: String) {
        state = .error
        message = "Не удалось подключиться"
        errorText = text
        haptic(.error)
    }

    private func describeSystem(_ error: Error) -> String {
        let ns = error as NSError
        var text = ns.localizedDescription
        if ns.domain.hasPrefix("NEVPN") {
            text += "\n\nТуннель завершился без объяснения. Чаще всего так бывает, если приложение подписано без права на VPN (Network Extension) — например, бесплатным Apple ID — или если туннелю не хватило памяти. Подробности в журнале."
        }
        return text
    }

    // MARK: stats

    private func startStats() {
        guard statsTimer == nil else { return }
        pollStats()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollStats() }
        }
    }

    private func stopStats() {
        statsTimer?.invalidate()
        statsTimer = nil
        rx = 0
        tx = 0
        transport = ""
    }

    private func pollStats() {
        guard let session = manager?.connection as? NETunnelProviderSession,
              let msg = Shared.messageStats.data(using: .utf8) else { return }
        try? session.sendProviderMessage(msg) { data in
            guard let data = data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            let rx = (json["rx"] as? NSNumber)?.uint64Value ?? 0
            let tx = (json["tx"] as? NSNumber)?.uint64Value ?? 0
            let transport = json["transport"] as? String ?? ""
            Task { @MainActor in
                self.rx = rx
                self.tx = tx
                self.transport = transport
            }
        }
    }

    /// The tunnel's log: live from the running tunnel, else the app group file.
    func fetchLog(_ done: @escaping (String) -> Void) {
        let fallback = Shared.readLog() ?? ""
        guard isActive,
              let session = manager?.connection as? NETunnelProviderSession,
              let msg = Shared.messageLog.data(using: .utf8) else {
            done(fallback.isEmpty ? Self.emptyLog : fallback)
            return
        }
        do {
            try session.sendProviderMessage(msg) { data in
                let live = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                let text = live.count >= fallback.count ? live : fallback
                Task { @MainActor in done(text.isEmpty ? Self.emptyLog : text) }
            }
        } catch {
            done(fallback.isEmpty ? Self.emptyLog : fallback)
        }
    }

    static let emptyLog = "Журнал пуст. Он появится после первой попытки подключения.\n\nЕсли журнал остаётся пустым после ошибки, туннель не смог даже запуститься: проверьте, что приложение подписано с правом на VPN (Network Extension)."

    // MARK: feedback

    func show(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled { self.toast = nil }
        }
    }

    enum Haptic { case medium, success, error }

    func haptic(_ kind: Haptic) {
        switch kind {
        case .medium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error: UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

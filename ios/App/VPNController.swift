import Foundation
import NetworkExtension

enum VPNState { case off, connecting, on, error }

/// Keeps the key and drives the system VPN profile of the tunnel extension.
@MainActor
final class VPNController: ObservableObject {
    @Published var state: VPNState = .off
    @Published var message = ""
    @Published var key: String? = UserDefaults.standard.string(forKey: "key")

    private var manager: NETunnelProviderManager?

    /// The extension's id follows the app's, so re-signing with another
    /// bundle id keeps them paired.
    private var extensionBundleId: String {
        (Bundle.main.bundleIdentifier ?? "com.hiseng.vpn") + ".tunnel"
    }

    init() {
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

    var keyTitle: String? {
        guard key != nil else { return nil }
        return "Ключ добавлен"
    }

    @discardableResult
    func saveKey(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = text.range(of: "openflux://[^\\s]+", options: .regularExpression) else {
            message = "Это не ключ OpenFlux"
            return false
        }
        let k = String(text[range])
        UserDefaults.standard.set(k, forKey: "key")
        key = k
        message = "Ключ сохранён"
        if state == .on || state == .connecting { stop() }
        return true
    }

    func toggle() {
        switch state {
        case .on, .connecting: stop()
        default: start()
        }
    }

    func start() {
        guard let key = key else {
            message = "Сначала вставьте ключ"
            return
        }
        state = .connecting
        message = "Подключаемся…"
        Task {
            let m = manager ?? NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = extensionBundleId
            proto.serverAddress = "Hiseng VPN"
            proto.providerConfiguration = ["link": key]
            m.protocolConfiguration = proto
            m.localizedDescription = "Hiseng VPN"
            m.isEnabled = true
            do {
                try await m.saveToPreferences()
                try await m.loadFromPreferences()
                manager = m
                try m.connection.startVPNTunnel()
            } catch {
                state = .error
                message = error.localizedDescription
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
            state = .on; message = "Защищено"
        case .connecting, .reasserting:
            state = .connecting; message = "Подключаемся…"
        case .disconnecting:
            state = .connecting; message = "Отключаемся…"
        case .disconnected, .invalid:
            if state == .connecting { fetchError(conn) }
            else if state != .error { state = .off; message = "" }
        @unknown default:
            state = .off
        }
    }

    private func fetchError(_ conn: NEVPNConnection) {
        if #available(iOS 16.0, *) {
            conn.fetchLastDisconnectError { err in
                Task { @MainActor in
                    if let err = err {
                        self.state = .error
                        self.message = err.localizedDescription
                    } else {
                        self.state = .off
                        self.message = ""
                    }
                }
            }
        } else {
            state = .off
            message = ""
        }
    }
}

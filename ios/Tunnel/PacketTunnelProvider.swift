import NetworkExtension

/// System VPN entry point: decodes the openflux:// key, starts the OpenFlux
/// core and moves IP packets between iOS and the core.
///
/// iOS reports any failure here only as a generic "internal error", so the
/// real reason and the core's log go to the app group (and are answered to
/// the app's messages while the tunnel runs).
final class PacketTunnelProvider: NEPacketTunnelProvider {

    private let lock = NSLock()
    private var running = false
    private var rx: UInt64 = 0
    private var tx: UInt64 = 0
    private var connectedOnce = false
    private var startedAt: Date?
    private var recent: [String] = []
    private var monitor: DispatchSourceTimer?
    private var transport = ""

    // MARK: start / stop

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        Shared.resetLog()
        Shared.writeError(nil)
        note("Запуск туннеля")

        let conf = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
        guard let link = conf["link"] as? String, link.hasPrefix("openflux://") else {
            finish(completionHandler, "Нет ключа. Добавьте ключ в приложении.")
            return
        }
        let profile: KeyProfile
        switch KeyProfile.decode(link) {
        case .success(let p): profile = p
        case .failure(let f):
            finish(completionHandler, f.message)
            return
        }
        note("Профиль «\(profile.name)», каналы: \(profile.transports.joined(separator: ", "))")

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        // 10.10.10.2 is the address every exit answers to.
        let ipv4 = NEIPv4Settings(addresses: ["10.10.10.2"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        settings.mtu = 1280
        // Queries to this address are answered by the core over DNS-over-TLS.
        let dns = NEDNSSettings(servers: ["198.18.0.1"])
        dns.matchDomains = [""]
        settings.dnsSettings = dns

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.finish(completionHandler, "iOS не принял настройки сети: \(error.localizedDescription)")
                return
            }
            // Connecting to the carriers can take a while: off the callback queue.
            DispatchQueue.global(qos: .userInitiated).async {
                let rc = self.startCore(profile)
                self.drainCoreLog()
                if rc != 0 {
                    self.finish(completionHandler, self.describeStart(rc))
                    return
                }
                self.lock.lock()
                self.running = true
                self.startedAt = Date()
                self.lock.unlock()
                self.note("Ядро запущено")
                self.startReadLoop()
                self.startWriteLoop()
                self.startMonitor()
                completionHandler(nil)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        lock.lock()
        running = false
        lock.unlock()
        monitor?.cancel()
        monitor = nil
        OpenFluxStopPacketTunnel()
        drainCoreLog()
        note("Туннель остановлен (причина \(reason.rawValue))")
        completionHandler()
    }

    private func startCore(_ p: KeyProfile) -> Int32 {
        if p.mode == "stream" {
            return p.streamType.withCString { t in
                p.streamURL.withCString { u in
                    OpenFluxStartStreamPacketTunnel(UnsafeMutablePointer(mutating: t),
                                                    UnsafeMutablePointer(mutating: u))
                }
            }
        }
        return p.session.withCString { s in
            p.secret.withCString { k in
                OpenFluxStartSessionPacketTunnel(UnsafeMutablePointer(mutating: s),
                                                 UnsafeMutablePointer(mutating: k))
            }
        }
    }

    private func describeStart(_ rc: Int32) -> String {
        let base: String
        switch rc {
        case 1: base = "Туннель уже запущен. Отключите VPN и попробуйте снова."
        case 2: base = "Ключ содержит неизвестный канал."
        case 3: base = "Не удалось подключиться к каналу сервера. Проверьте интернет и что сервер работает."
        case 4: base = "Адрес уже занят."
        case 5: base = "Внутренняя ошибка ядра OpenFlux."
        case 6: base = "Неверный секрет шифрования в ключе."
        default: base = "Ошибка запуска (код \(rc))."
        }
        // The core's own reason is in its last error line.
        let reason = recentLines().last { $0.contains("[ERROR]") || $0.contains("start:") }
        if let reason = reason {
            return base + "\n" + reason
        }
        return base
    }

    // MARK: packets

    /// iPhone -> core.
    private func startReadLoop() {
        packetFlow.readPackets { [weak self] packets, _ in
            guard let self = self, self.isRunning else { return }
            var n: UInt64 = 0
            for p in packets {
                n += UInt64(p.count)
                p.withUnsafeBytes { raw in
                    if let base = raw.bindMemory(to: CChar.self).baseAddress {
                        OpenFluxTunWritePacket(UnsafeMutablePointer(mutating: base), Int32(p.count))
                    }
                }
            }
            self.lock.lock()
            self.tx &+= n
            self.lock.unlock()
            self.startReadLoop()
        }
    }

    /// Core -> iPhone.
    private func startWriteLoop() {
        let thread = Thread { [weak self] in
            guard let self = self else { return }
            let maxLen: Int32 = 65535
            let buf = UnsafeMutablePointer<CChar>.allocate(capacity: Int(maxLen))
            defer { buf.deallocate() }
            while self.isRunning {
                let n = OpenFluxTunReadPacket(buf, maxLen)
                if n <= 0 { break }
                let data = Data(bytes: buf, count: Int(n))
                self.lock.lock()
                self.rx &+= UInt64(n)
                self.lock.unlock()
                self.packetFlow.writePackets([data], withProtocols: [NSNumber(value: AF_INET)])
            }
        }
        thread.name = "hiseng.tun.write"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    private var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    // MARK: monitor

    /// Every 2 s: moves the core's log out and tells iOS when the carrier is
    /// lost and found again (the VPN icon shows reconnecting meanwhile).
    private func startMonitor() {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        t.schedule(deadline: .now() + 1, repeating: 2)
        t.setEventHandler { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.drainCoreLog()
            let on = OpenFluxPacketTunnelConnected() != 0
            if let name = self.coreString(OpenFluxActiveTransport()), !name.isEmpty {
                self.lock.lock()
                self.transport = name
                self.lock.unlock()
            }
            self.lock.lock()
            let first = on && !self.connectedOnce
            if on { self.connectedOnce = true }
            let seen = self.connectedOnce
            self.lock.unlock()
            if first { self.note("Канал до сервера установлен") }
            if seen && self.reasserting == on {
                self.reasserting = !on
                self.note(on ? "Связь восстановлена" : "Связь потеряна, переподключаемся…")
            }
        }
        t.resume()
        monitor = t
    }

    // MARK: messages from the app

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        let msg = String(decoding: messageData, as: UTF8.self)
        switch msg {
        case Shared.messageLog:
            drainCoreLog()
            completionHandler?(recentLines().joined(separator: "\n").data(using: .utf8))
        default:
            lock.lock()
            let info: [String: Any] = [
                "rx": rx,
                "tx": tx,
                "connected": OpenFluxPacketTunnelConnected() != 0,
                "transport": KeyProfile.prettyTransport(transport),
                "since": startedAt?.timeIntervalSince1970 ?? 0,
            ]
            lock.unlock()
            completionHandler?(try? JSONSerialization.data(withJSONObject: info))
        }
    }

    // MARK: log

    private func coreString(_ p: UnsafeMutablePointer<CChar>?) -> String? {
        guard let p = p else { return nil }
        defer { OpenFluxFreeString(p) }
        return String(cString: p)
    }

    private func drainCoreLog() {
        guard let text = coreString(OpenFluxReadLog()), !text.isEmpty else { return }
        for line in text.split(separator: "\n") where !line.isEmpty {
            remember(String(line))
        }
        Shared.appendLog(text)
    }

    private func note(_ text: String) {
        let line = "\(Shared.timestamp()) [APP] \(text)"
        remember(line)
        Shared.appendLog(line)
    }

    private func remember(_ line: String) {
        lock.lock()
        recent.append(line)
        if recent.count > 400 { recent.removeFirst(recent.count - 400) }
        lock.unlock()
    }

    private func recentLines() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return recent
    }

    private func finish(_ completion: (Error?) -> Void, _ message: String) {
        drainCoreLog()
        note("Ошибка: \(message)")
        Shared.writeError(message)
        completion(NSError(domain: "HisengVPN", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
    }
}

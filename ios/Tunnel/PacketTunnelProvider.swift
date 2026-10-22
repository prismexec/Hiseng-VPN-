import NetworkExtension

/// System VPN entry point: decodes the openflux:// key, starts the OpenFlux
/// core in Session mode and moves IP packets between iOS and the core.
class PacketTunnelProvider: NEPacketTunnelProvider {

    private var running = false

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let conf = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
        guard let link = conf["link"] as? String, link.hasPrefix("openflux://") else {
            completionHandler(fail("Нет ключа"))
            return
        }

        // The core reads the link itself: session profile + secret.
        guard let decoded = callString({ OpenFluxShareDecode($0) }, link),
              let data = decoded.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            completionHandler(fail("Не удалось прочитать ключ"))
            return
        }
        if let err = json["error"] as? String {
            completionHandler(fail("Ключ повреждён: \(err)"))
            return
        }
        let secret = (json["config"] as? [String: Any])?["secret"] as? String ?? ""
        var session = ""
        if let s = json["session"] as? String {
            session = s
        } else if let obj = json["session"],
                  let d = try? JSONSerialization.data(withJSONObject: obj),
                  let s = String(data: d, encoding: .utf8) {
            session = s
        }
        if session.isEmpty {
            completionHandler(fail("В ключе нет профиля"))
            return
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let ipv4 = NEIPv4Settings(addresses: ["10.10.10.2"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        settings.mtu = 1280
        let dns = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        dns.matchDomains = [""]
        settings.dnsSettings = dns

        setTunnelNetworkSettings(settings) { error in
            if let error = error {
                completionHandler(error)
                return
            }
            let rc = session.withCString { s in
                secret.withCString { k in
                    OpenFluxStartSessionPacketTunnel(UnsafeMutablePointer(mutating: s),
                                                     UnsafeMutablePointer(mutating: k))
                }
            }
            if rc != 0 {
                let log = self.readLog()
                completionHandler(self.fail("Ошибка запуска (\(rc)) \(log.suffix(300))"))
                return
            }
            self.running = true
            self.startReadLoop()
            self.startWriteLoop()
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        running = false
        OpenFluxStopPacketTunnel()
        completionHandler()
    }

    /// iPhone -> core.
    private func startReadLoop() {
        packetFlow.readPackets { [weak self] packets, _ in
            guard let self = self, self.running else { return }
            for p in packets {
                p.withUnsafeBytes { raw in
                    if let base = raw.bindMemory(to: CChar.self).baseAddress {
                        OpenFluxTunWritePacket(UnsafeMutablePointer(mutating: base), Int32(p.count))
                    }
                }
            }
            self.startReadLoop()
        }
    }

    /// Core -> iPhone.
    private func startWriteLoop() {
        DispatchQueue.global(qos: .userInitiated).async {
            let maxLen: Int32 = 65535
            let buf = UnsafeMutablePointer<CChar>.allocate(capacity: Int(maxLen))
            defer { buf.deallocate() }
            while self.running {
                let n = OpenFluxTunReadPacket(buf, maxLen)
                if n <= 0 { break }
                let data = Data(bytes: buf, count: Int(n))
                let proto = (data.first.map { $0 >> 4 } == 6) ? AF_INET6 : AF_INET
                self.packetFlow.writePackets([data], withProtocols: [NSNumber(value: proto)])
            }
        }
    }

    private func readLog() -> String {
        guard let p = OpenFluxReadLog() else { return "" }
        defer { OpenFluxFreeString(p) }
        return String(cString: p)
    }

    private func callString(_ f: (UnsafeMutablePointer<CChar>) -> UnsafeMutablePointer<CChar>?, _ arg: String) -> String? {
        arg.withCString { a in
            guard let r = f(UnsafeMutablePointer(mutating: a)) else { return nil }
            defer { OpenFluxFreeString(r) }
            return String(cString: r)
        }
    }

    private func fail(_ msg: String) -> NSError {
        NSError(domain: "HisengVPN", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}

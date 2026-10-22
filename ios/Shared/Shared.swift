import Foundation
import os

/// Code shared by the app and the tunnel extension: the key decoder and the
/// files both sides read through the app group (last error, tunnel log).
enum Shared {
    /// App group of the app and the extension: the one this binary is
    /// actually signed with (re-signing tools rename it), else ours. Without
    /// the entitlement the container is nil and the app falls back to
    /// messages sent to the running tunnel.
    static let groupID: String = Signing.current?.groups.first ?? "group.com.hiseng.vpn"

    static var groupAvailable: Bool {
        guard let url = container else { return false }
        let probe = url.appendingPathComponent(".probe")
        guard (try? Data("1".utf8).write(to: probe, options: .atomic)) != nil else { return false }
        try? FileManager.default.removeItem(at: probe)
        return true
    }

    /// Messages the app sends to the running tunnel.
    static let messageStats = "stats"
    static let messageLog = "log"

    private static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    private static var errorURL: URL? { container?.appendingPathComponent("last_error.txt") }
    private static var logURL: URL? { container?.appendingPathComponent("tunnel.log") }

    // MARK: last error

    static func writeError(_ text: String?) {
        guard let url = errorURL else { return }
        if let text = text, !text.isEmpty {
            try? text.data(using: .utf8)?.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func readError() -> String? {
        guard let url = errorURL, let data = try? Data(contentsOf: url) else { return nil }
        let s = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    // MARK: tunnel log

    private static let logLimit = 256 * 1024

    static func resetLog() {
        guard let url = logURL else { return }
        try? Data().write(to: url, options: .atomic)
    }

    static func appendLog(_ text: String) {
        guard let url = logURL, !text.isEmpty else { return }
        let line = text.hasSuffix("\n") ? text : text + "\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            let size = h.offsetInFile
            h.closeFile()
            if size > UInt64(logLimit) { trimLog(url) }
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func readLog() -> String? {
        guard let url = logURL, let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func trimLog(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let tail = data.suffix(logLimit / 2)
        try? Data(tail).write(to: url, options: .atomic)
    }

    /// Memory this process uses as iOS counts it for its limit, in MB.
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    /// "used 31.2 MB, 18.8 MB left before iOS ends the process".
    static func memoryLine() -> String {
        let used = String(format: "%.1f", footprintMB())
        let left = String(format: "%.1f", Double(os_proc_available_memory()) / 1_048_576)
        return "память \(used) МБ, до лимита iOS \(left) МБ"
    }

    static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}

/// An openflux:// key as the core reads it. The link is never interpreted in
/// Swift: the core decodes it and builds the session profile.
struct KeyProfile {
    var link: String
    var name: String
    var transports: [String]
    var secret: String
    var session: String
    /// "stream" for a PHP exit, "" for the usual tunnel.
    var mode: String
    var streamType: String
    var streamURL: String
    /// host:port of every carrier that dials the exit itself ("direct").
    var dials: [String]

    struct Failure: Error {
        let message: String
    }

    static func decode(_ link: String) -> Result<KeyProfile, Failure> {
        let raw = link.withCString { a -> String? in
            guard let r = OpenFluxShareDecode(UnsafeMutablePointer(mutating: a)) else { return nil }
            defer { OpenFluxFreeString(r) }
            return String(cString: r)
        }
        guard let text = raw,
              let data = text.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failure(Failure(message: "Не удалось прочитать ключ"))
        }
        let code = json["code"] as? String
        if code != nil || json["error"] != nil {
            return .failure(Failure(message: describe(code: code ?? "", param: json["param"] as? String)))
        }
        guard let config = json["config"] as? [String: Any] else {
            return .failure(Failure(message: "В ключе нет настроек"))
        }
        let list = (config["transports"] as? [[String: Any]]) ?? []
        let names: [String] = list.compactMap { t in
            let type = t["type"] as? String ?? ""
            let name = t["name"] as? String ?? ""
            let shown = name.isEmpty ? type : name
            return shown.isEmpty ? nil : prettyTransport(shown)
        }
        var session = ""
        if let s = json["session"] as? String {
            session = s
        } else if let obj = json["session"],
                  let d = try? JSONSerialization.data(withJSONObject: obj),
                  let s = String(data: d, encoding: .utf8) {
            session = s
        }
        let mode = config["mode"] as? String ?? ""
        let first = list.first ?? [:]
        let profile = KeyProfile(
            link: link,
            name: (config["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Мой сервер",
            transports: names,
            secret: config["secret"] as? String ?? "",
            session: session,
            mode: mode,
            streamType: first["type"] as? String ?? "",
            streamURL: first["url"] as? String ?? "",
            dials: list.compactMap { ($0["dial"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        )
        if mode != "stream" && session.isEmpty {
            return .failure(Failure(message: "В ключе нет профиля подключения"))
        }
        return .success(profile)
    }

    /// Words the core's share.Code* for the user.
    static func describe(code: String, param: String?) -> String {
        switch code {
        case "not_link": return "Это не ключ Hiseng VPN"
        case "unsupported_version": return "Ключ от более новой версии приложения — обновите его"
        case "case_changed": return "Ключ испорчен: изменился регистр букв (часто так делают мессенджеры)"
        case "damaged": return "Ключ повреждён или обрезан при копировании"
        case "too_large": return "Ключ слишком длинный"
        case "bad_payload", "bad_config": return "Ключ повреждён"
        case "no_transports": return "В ключе нет ни одного канала"
        case "unknown_transport": return "Неизвестный канал в ключе\(param.map { ": \($0)" } ?? "")"
        case "session_secret", "short_secret": return "В ключе слишком короткий секрет"
        case "unknown_codec": return "Неизвестный кодек в ключе"
        case "unknown_mode": return "Неизвестный режим в ключе"
        default: return "Ключ не подходит\(code.isEmpty ? "" : " (\(code))")"
        }
    }

    static func prettyTransport(_ t: String) -> String {
        switch t.lowercased() {
        case "yandex": return "Яндекс Документы"
        case "boards": return "Доски"
        case "mailru": return "Mail.ru"
        case "direct": return "Напрямую"
        default: return t
        }
    }
}

/// What a binary is really signed with: the entitlements in its code
/// signature. Sideloading tools re-sign apps and may drop the VPN right or
/// rename the app group, which iOS only reports as an "internal error".
struct Signing {
    var entitlements: [String: Any]

    var groups: [String] {
        entitlements["com.apple.security.application-groups"] as? [String] ?? []
    }

    var networkExtension: [String] {
        entitlements["com.apple.developer.networking.networkextension"] as? [String] ?? []
    }

    var hasPacketTunnel: Bool {
        networkExtension.contains { $0.hasPrefix("packet-tunnel-provider") }
    }

    var teamID: String? {
        entitlements["com.apple.developer.team-identifier"] as? String
    }

    /// "TEAMID.bundle.id" the binary is signed for; iOS refuses to launch a
    /// binary whose bundle id it does not cover.
    var applicationID: String? {
        entitlements["application-identifier"] as? String
    }

    /// Whether the signed application-identifier covers this bundle id
    /// (exactly or with a "TEAMID.*" style wildcard).
    func covers(bundleID: String) -> Bool? {
        guard let appID = applicationID, let dot = appID.firstIndex(of: ".") else { return nil }
        let pattern = String(appID[appID.index(after: dot)...])
        if pattern == "*" { return true }
        if pattern.hasSuffix(".*") { return bundleID.hasPrefix(String(pattern.dropLast(1))) }
        return pattern == bundleID
    }

    /// This process's own binary.
    static let current: Signing? = Bundle.main.executableURL.flatMap { read(executable: $0) }

    /// Reads the entitlements blob (magic 0xfade7171) from the end of a
    /// Mach-O, where the code signature lives.
    static func read(executable url: URL) -> Signing? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { h.closeFile() }
        let size = h.seekToEndOfFile()
        let window: UInt64 = 4 << 20
        h.seek(toFileOffset: size > window ? size - window : 0)
        let data = h.readDataToEndOfFile()
        let magic: [UInt8] = [0xFA, 0xDE, 0x71, 0x71]
        var i = data.startIndex
        while let r = data.range(of: Data(magic), in: i..<data.endIndex) {
            let lenStart = r.upperBound
            guard lenStart + 4 <= data.endIndex else { break }
            let len = data[lenStart..<lenStart + 4].reduce(0) { ($0 << 8) | Int($1) }
            let bodyStart = lenStart + 4
            let bodyEnd = r.lowerBound + len
            if len > 8, bodyEnd <= data.endIndex,
               let plist = try? PropertyListSerialization.propertyList(
                   from: data[bodyStart..<bodyEnd], options: [], format: nil) as? [String: Any] {
                return Signing(entitlements: plist)
            }
            i = r.upperBound
        }
        return nil
    }
}

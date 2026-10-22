import Foundation
import UIKit

/// Checks of how the installed app was signed. Sideloading tools re-sign the
/// app; when they drop the tunnel module or the VPN right, iOS only says
/// "internal error", so the app says what is actually wrong.
enum Diagnostics {
    struct Tunnel {
        var url: URL
        var bundleID: String?
        var signing: Signing?
    }

    /// The packet tunnel extension inside this app, as installed.
    static var tunnel: Tunnel? {
        guard let dir = Bundle.main.builtInPlugInsURL,
              let items = try? FileManager.default.contentsOfDirectory(
                  at: dir, includingPropertiesForKeys: nil) else { return nil }
        for url in items where url.pathExtension == "appex" {
            guard let b = Bundle(url: url) else { continue }
            let ext = b.object(forInfoDictionaryKey: "NSExtension") as? [String: Any]
            let point = ext?["NSExtensionPointIdentifier"] as? String ?? ""
            if point.contains("packet-tunnel") || url.lastPathComponent.hasPrefix("HisengTunnel") {
                return Tunnel(url: url, bundleID: b.bundleIdentifier,
                              signing: b.executableURL.flatMap { Signing.read(executable: $0) })
            }
        }
        return nil
    }

    struct Profile {
        var name: String
        var team: String
        var expires: Date?
        var enterprise: Bool
        var vpn: Bool
        var appID: String
    }

    /// embedded.mobileprovision of a bundle (absent for TrollStore installs).
    static func profile(in dir: URL) -> Profile? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("embedded.mobileprovision")),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = (try? PropertyListSerialization.propertyList(
                  from: data[start.lowerBound..<end.upperBound], options: [], format: nil)) as? [String: Any]
        else { return nil }
        let ent = plist["Entitlements"] as? [String: Any] ?? [:]
        let ne = ent["com.apple.developer.networking.networkextension"] as? [String] ?? []
        return Profile(
            name: plist["Name"] as? String ?? "?",
            team: plist["TeamName"] as? String ?? "?",
            expires: plist["ExpirationDate"] as? Date,
            enterprise: plist["ProvisionsAllDevices"] as? Bool ?? false,
            vpn: ne.contains { $0.hasPrefix("packet-tunnel-provider") },
            appID: ent["application-identifier"] as? String ?? "?"
        )
    }

    /// The one problem that explains a failed start, if the signing shows it.
    static func problem() -> String? {
        guard let t = tunnel else {
            return "В установленном приложении нет модуля туннеля (HisengTunnel.appex). Программа, которой вы подписывали IPA, удалила расширения — включите в ней сохранение расширений (PlugIns / App Extensions) и переустановите."
        }
        if let s = t.signing, let id = t.bundleID, s.covers(bundleID: id) == false {
            return "Модуль туннеля подписан чужим профилем: его подпись выдана для «\(s.applicationID ?? "?")», а сам он — «\(id)». iOS такой модуль не запускает. Программа подписи должна подписывать расширение отдельным профилем (для «\(id)») — включите в ней подпись расширений / автоматическую регистрацию App ID или используйте другой сервис подписи."
        }
        if let s = t.signing, !s.hasPacketTunnel {
            return "Модуль туннеля подписан без права на VPN (Network Extension). Сертификат, которым подписано приложение, не позволяет VPN-приложения: iOS не даёт туннелю запуститься. Нужен сертификат разработчика с возможностью Network Extensions (или установка через TrollStore)."
        }
        if let s = Signing.current, !s.hasPacketTunnel {
            return "Приложение подписано без права на VPN (Network Extension), поэтому iOS не запускает туннель. Нужен сертификат с возможностью Network Extensions (или установка через TrollStore)."
        }
        if let p = profile(in: t.url), let exp = p.expires, exp < Date() {
            return "Срок действия профиля подписи «\(p.name)» истёк. Переподпишите приложение."
        }
        return nil
    }

    /// Human-readable report placed above the tunnel log.
    static func report() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let df = DateFormatter()
        df.dateFormat = "dd.MM.yyyy"
        var lines: [String] = ["=== Диагностика ==="]
        lines.append("Приложение: \(Bundle.main.bundleIdentifier ?? "?") v\(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?")), iOS \(UIDevice.current.systemVersion)")

        let app = Signing.current
        lines.append("Право на VPN у приложения: \(yes(app?.hasPacketTunnel, unknown: app == nil))")
        lines.append("Подпись приложения выдана для: \(app?.applicationID ?? "?") — \(match(app, Bundle.main.bundleIdentifier))")
        lines.append("Память приложения: \(Shared.memoryLine())")
        if let t = tunnel {
            lines.append("Модуль туннеля: \(t.bundleID ?? "?")")
            lines.append("Подпись туннеля выдана для: \(t.signing?.applicationID ?? "?") — \(match(t.signing, t.bundleID))")
            if let p = profile(in: t.url) {
                lines.append("Профиль туннеля: «\(p.name)», для \(p.appID), VPN: \(p.vpn ? "да" : "НЕТ")")
            } else {
                lines.append("Профиль туннеля: нет")
            }
            lines.append("Право на VPN у туннеля: \(yes(t.signing?.hasPacketTunnel, unknown: t.signing == nil))")
            let tg = t.signing?.groups ?? []
            lines.append("Группа туннеля: \(tg.isEmpty ? "нет" : tg.joined(separator: ", "))")
        } else {
            lines.append("Модуль туннеля: НЕ НАЙДЕН")
        }
        let ag = app?.groups ?? []
        lines.append("Группа приложения: \(ag.isEmpty ? "нет" : ag.joined(separator: ", ")) — \(Shared.groupAvailable ? "доступна" : "недоступна")")
        if let team = app?.teamID { lines.append("Команда подписи: \(team)") }

        if let p = profile(in: Bundle.main.bundleURL) {
            var s = "Профиль: «\(p.name)», \(p.team)"
            if p.enterprise { s += ", корпоративный" }
            if let e = p.expires { s += ", до \(df.string(from: e))" }
            s += ", для \(p.appID), VPN в профиле: \(p.vpn ? "да" : "НЕТ")"
            lines.append(s)
        } else {
            lines.append("Профиль: нет (ad-hoc или TrollStore)")
        }
        if let p = problem() {
            lines.append("")
            lines.append("⚠️ \(p)")
        } else {
            lines.append("Проблем с подписью не найдено.")
            lines.append("Если журнал туннеля ниже пуст или в нём нет строки «Процесс туннеля запущен», iOS не смогла запустить модуль: пришлите файлы «HisengTunnel…» из Настройки → Конфиденциальность и безопасность → Аналитика и улучшения → Данные аналитики.")
        }
        return lines.joined(separator: "\n")
    }

    private static func match(_ s: Signing?, _ id: String?) -> String {
        guard let s = s, let id = id, let ok = s.covers(bundleID: id) else { return "не удалось проверить" }
        return ok ? "совпадает" : "НЕ СОВПАДАЕТ с \(id)"
    }

    private static func yes(_ v: Bool?, unknown: Bool) -> String {
        if unknown { return "не удалось прочитать" }
        return v == true ? "есть" : "НЕТ"
    }
}

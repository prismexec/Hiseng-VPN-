import Foundation
import UIKit

/// Over-the-air updates for a sideloaded app: iOS cannot replace it by
/// itself, so the app finds a newer build in the GitHub releases and hands
/// the IPA to the user's signing app (or the install source does it).
@MainActor
final class Updater: ObservableObject {
    struct Release: Equatable {
        var build: Int
        var page: URL
        var ipa: URL?
        var notes: String
    }

    @Published private(set) var available: Release?
    @Published private(set) var checking = false

    /// Public releases repo first; the main repo answers once it is public.
    static let repos = ["prismexec/hiseng-vpn-releases", "prismexec/Hiseng-VPN-"]
    /// AltStore-format source; ESign, Feather and AltStore show updates from it.
    static let sourceURL = "https://raw.githubusercontent.com/\(repos[0])/main/altstore.json"

    static var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    static var versionText: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return "\(v) (сборка \(currentBuild))"
    }

    /// Looks for an iOS release newer than this build. Returns a line for
    /// the user when `manual`.
    @discardableResult
    func check(manual: Bool = false) async -> String? {
        guard !checking else { return nil }
        checking = true
        defer { checking = false }
        var list: [[String: Any]]?
        for repo in Self.repos {
            guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=30") else { continue }
            var req = URLRequest(url: url)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 15
            if let answer = try? await URLSession.shared.data(for: req),
               (answer.1 as? HTTPURLResponse)?.statusCode == 200,
               let l = (try? JSONSerialization.jsonObject(with: answer.0)) as? [[String: Any]] {
                list = l
                break
            }
        }
        guard let list = list else {
            return manual ? "Сервер обновлений пока недоступен" : nil
        }
        var best: Release?
        for r in list {
            guard let tag = r["tag_name"] as? String, tag.hasPrefix("ios-"),
                  let n = Int(tag.dropFirst(4)),
                  (r["draft"] as? Bool) != true,
                  n > (best?.build ?? 0),
                  let page = (r["html_url"] as? String).flatMap(URL.init(string:)) else { continue }
            let assets = r["assets"] as? [[String: Any]] ?? []
            let ipa = assets
                .first { ($0["name"] as? String)?.hasSuffix(".ipa") == true }
                .flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init(string:)) }
            best = Release(build: n, page: page, ipa: ipa, notes: r["body"] as? String ?? "")
        }
        if let b = best, b.build > Self.currentBuild {
            available = b
            return manual ? "Есть новая сборка \(b.build)" : nil
        }
        available = nil
        return manual ? "Установлена последняя версия" : nil
    }

    func download() {
        guard let r = available else { return }
        UIApplication.shared.open(r.ipa ?? r.page)
    }
}

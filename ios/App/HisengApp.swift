import SwiftUI

@main
struct HisengApp: App {
    @StateObject private var vpn = VPNController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vpn)
                .onOpenURL { url in vpn.saveKey(url.absoluteString) }
        }
    }
}

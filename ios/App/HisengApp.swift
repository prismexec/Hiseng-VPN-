import SwiftUI
import UIKit

@main
struct HisengApp: App {
    @StateObject private var vpn = VPNController()

    init() {
        // TextEditor draws on its own background otherwise (iOS 15).
        UITextView.appearance().backgroundColor = .clear
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vpn)
                .onOpenURL { url in vpn.saveKey(url.absoluteString) }
        }
    }
}

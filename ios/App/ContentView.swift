import SwiftUI
import UIKit

/// Wavy "cookie" outline like Material 3 Expressive shapes.
struct CookieShape: Shape {
    var waves: Double
    var depth: Double
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(waves, depth) }
        set { waves = newValue.first; depth = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let base = min(rect.width, rect.height) / 2 * (1 - depth)
        var p = Path()
        let steps = 360
        for i in 0...steps {
            let a = Double(i) / Double(steps) * 2 * .pi
            let r = base + base * depth / (1 - depth) * cos(waves * a)
            let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

struct ContentView: View {
    @EnvironmentObject var vpn: VPNController
    @State private var spin = false
    @State private var pressed = false
    @State private var showEnter = false
    @State private var typed = ""

    private let accent = Color(red: 0.42, green: 0.36, blue: 0.91)
    private let green = Color(red: 0.0, green: 0.78, blue: 0.59)

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    Text("Hiseng VPN")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .padding(.top, 24)

                    powerButton
                        .padding(.top, 44)

                    Text(statusTitle)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(vpn.state == .on ? green : .primary)
                        .padding(.top, 32)
                        .animation(.easeInOut, value: vpn.state)

                    Text(statusHint)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                        .padding(.horizontal, 24)

                    keyCard
                        .padding(.top, 36)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .sheet(isPresented: $showEnter) { enterSheet }
        .onAppear { spin = true }
    }

    private var statusTitle: String {
        switch vpn.state {
        case .off: return "Отключено"
        case .connecting: return "Подключение"
        case .on: return "Подключено"
        case .error: return "Ошибка"
        }
    }

    private var statusHint: String {
        if !vpn.message.isEmpty { return vpn.message }
        return vpn.key == nil ? "Добавьте ключ ниже" : "Нажмите, чтобы подключиться"
    }

    private var buttonColor: Color {
        switch vpn.state {
        case .on: return green
        case .connecting: return accent.opacity(0.85)
        case .error: return Color.red.opacity(0.8)
        case .off: return Color(UIColor.secondarySystemBackground)
        }
    }

    private var iconColor: Color {
        vpn.state == .off ? accent : .white
    }

    private var powerButton: some View {
        let waves: Double = vpn.state == .on ? 12 : (vpn.state == .connecting ? 7 : 9)
        let rotating = vpn.state == .on || vpn.state == .connecting
        return ZStack {
            CookieShape(waves: waves, depth: 0.07)
                .fill(buttonColor)
                .overlay(
                    CookieShape(waves: waves, depth: 0.07)
                        .stroke(accent, lineWidth: vpn.state == .off ? 4 : 0)
                )
                .rotationEffect(.degrees(rotating && spin ? 360 : 0))
                .animation(rotating
                           ? .linear(duration: vpn.state == .connecting ? 4 : 24).repeatForever(autoreverses: false)
                           : .default,
                           value: spin && rotating)
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: waves)

            if vpn.state == .connecting {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(2.2)
            } else {
                Image(systemName: "power")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundColor(iconColor)
            }
        }
        .frame(width: 232, height: 232)
        .scaleEffect(pressed ? 0.9 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.45), value: pressed)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: 0, pressing: { pressed = $0 }, perform: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            vpn.toggle()
        })
    }

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    CookieShape(waves: 6, depth: 0.08)
                        .fill(vpn.key != nil ? green.opacity(0.25) : accent.opacity(0.2))
                    Text(vpn.key != nil ? "✓" : "?")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(vpn.key != nil ? green : accent)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vpn.keyTitle ?? "Ключ не добавлен")
                        .font(.headline)
                    Text(vpn.key == nil ? "Скопируйте ключ openflux:// и вставьте"
                                        : String(vpn.key!.prefix(32)) + "…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            Button {
                if let s = UIPasteboard.general.string { vpn.saveKey(s) }
                else { vpn.message = "Буфер обмена пуст" }
            } label: {
                Text("Вставить ключ из буфера")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .foregroundColor(.white)
                    .background(accent)
                    .clipShape(Capsule())
            }
            .padding(.top, 18)

            Button {
                typed = vpn.key ?? ""
                showEnter = true
            } label: {
                Text("Ввести вручную")
                    .font(.system(size: 16, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundColor(accent)
                    .background(accent.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(.top, 10)
        }
        .padding(20)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private var enterSheet: some View {
        NavigationView {
            VStack(spacing: 16) {
                TextEditor(text: $typed)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 160)
                    .padding(8)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Spacer()
            }
            .padding()
            .navigationTitle("Ключ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { showEnter = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        if vpn.saveKey(typed) { showEnter = false }
                    }
                }
            }
        }
    }
}

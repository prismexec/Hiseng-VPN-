import SwiftUI
import UIKit

// MARK: - Palette

enum Palette {
    static let bg = Color(red: 0.035, green: 0.035, blue: 0.06)
    static let indigo = Color(red: 0.45, green: 0.40, blue: 1.0)
    static let violet = Color(red: 0.66, green: 0.36, blue: 1.0)
    static let mint = Color(red: 0.12, green: 0.86, blue: 0.62)
    static let teal = Color(red: 0.0, green: 0.62, blue: 0.86)
    static let amber = Color(red: 1.0, green: 0.70, blue: 0.20)
    static let coral = Color(red: 1.0, green: 0.36, blue: 0.40)
    static let text2 = Color.white.opacity(0.62)
    static let text3 = Color.white.opacity(0.38)
    static let card = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.09)

    static func main(_ s: VPNState) -> Color {
        switch s {
        case .off: return indigo
        case .connecting, .reconnecting, .disconnecting: return amber
        case .on: return mint
        case .error: return coral
        }
    }

    static func second(_ s: VPNState) -> Color {
        switch s {
        case .off: return violet
        case .connecting, .reconnecting, .disconnecting: return coral
        case .on: return teal
        case .error: return violet
        }
    }
}

// MARK: - Screen

struct ContentView: View {
    @EnvironmentObject var vpn: VPNController
    @State private var showEnter = false
    @State private var showLog = false

    var body: some View {
        ZStack(alignment: .top) {
            AuroraBackground(a: Palette.main(vpn.state), b: Palette.second(vpn.state))
                .animation(.easeInOut(duration: 0.8), value: vpn.state)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 8)

                    PowerOrb(state: vpn.state) { vpn.toggle() }
                        .frame(width: 250, height: 250)
                        .padding(.top, 34)

                    status
                        .padding(.top, 26)

                    if vpn.state == .on {
                        StatsRow(rx: vpn.rx, tx: vpn.tx, transport: vpn.transport)
                            .padding(.top, 26)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if vpn.state == .error, let err = vpn.errorText {
                        ErrorCard(text: err) { showLog = true }
                            .padding(.top, 22)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }

                    KeyCard(showEnter: $showEnter)
                        .padding(.top, 22)

                    Text("Работает на OpenFlux · GPL-3.0")
                        .font(.caption2)
                        .foregroundColor(Palette.text3)
                        .padding(.top, 22)
                        .padding(.bottom, 30)
                }
                .padding(.horizontal, 18)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: vpn.state)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: vpn.errorText)
            }

            if let t = vpn.toast {
                Toast(text: t)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: vpn.toast)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showEnter) { EnterKeySheet().environmentObject(vpn) }
        .sheet(isPresented: $showLog) { LogSheet().environmentObject(vpn) }
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 10) {
                Logo()
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Hiseng")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                    Text("VPN")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .kerning(3)
                        .foregroundColor(Palette.text2)
                }
            }
            Spacer()
            CircleIconButton(system: "doc.text.magnifyingglass") { showLog = true }
        }
        .foregroundColor(.white)
    }

    private var status: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .id(title)
                .transition(.opacity)

            if vpn.state == .on, let since = vpn.connectedSince {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(Self.elapsed(from: since, to: ctx.date))
                        .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundColor(Palette.mint)
                }
            } else {
                Text(subtitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Palette.text2)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var title: String {
        switch vpn.state {
        case .off: return "Отключено"
        case .connecting: return "Подключение"
        case .reconnecting: return "Переподключение"
        case .disconnecting: return "Отключение"
        case .on: return "Защищено"
        case .error: return "Ошибка"
        }
    }

    private var subtitle: String {
        switch vpn.state {
        case .off: return vpn.key == nil ? "Добавьте ключ, чтобы начать" : "Нажмите, чтобы подключиться"
        case .error: return vpn.message
        default: return vpn.message
        }
    }

    static func elapsed(from: Date, to: Date) -> String {
        let s = max(0, Int(to.timeIntervalSince(from)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
}

// MARK: - Background

struct AuroraBackground: View {
    var a: Color
    var b: Color
    @State private var drift = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                Palette.bg
                Circle()
                    .fill(a.opacity(0.55))
                    .frame(width: w * 1.1, height: w * 1.1)
                    .blur(radius: 90)
                    .offset(x: drift ? -w * 0.25 : w * 0.15, y: drift ? -w * 0.55 : -w * 0.35)
                Circle()
                    .fill(b.opacity(0.40))
                    .frame(width: w * 0.9, height: w * 0.9)
                    .blur(radius: 100)
                    .offset(x: drift ? w * 0.35 : -w * 0.05, y: drift ? w * 0.05 : -w * 0.15)
                Circle()
                    .fill(a.opacity(0.18))
                    .frame(width: w, height: w)
                    .blur(radius: 120)
                    .offset(x: drift ? -w * 0.1 : w * 0.2, y: drift ? w * 0.9 : w * 0.7)
                LinearGradient(colors: [.clear, Palette.bg.opacity(0.85)],
                               startPoint: .center, endPoint: .bottom)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

// MARK: - Power orb

struct PowerOrb: View {
    var state: VPNState
    var action: () -> Void

    @State private var spin = false
    @State private var breathe = false
    @State private var ripple = false

    private var busy: Bool {
        state == .connecting || state == .reconnecting || state == .disconnecting
    }

    var body: some View {
        let c = Palette.main(state)
        let c2 = Palette.second(state)
        ZStack {
            // Glow.
            Circle()
                .fill(c.opacity(state == .off ? 0.22 : 0.45))
                .blur(radius: 46)
                .scaleEffect(breathe ? 1.08 : 0.92)

            // Ripples while connecting.
            ForEach(0..<3) { i in
                Circle()
                    .stroke(c.opacity(busy ? 0.5 : 0), lineWidth: 1.5)
                    .scaleEffect(ripple ? 1.35 : 0.72)
                    .opacity(ripple ? 0 : 1)
                    .animation(.easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(Double(i) * 0.8),
                               value: ripple)
            }

            // Track.
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 10)
                .padding(14)

            // Progress / state ring.
            Circle()
                .trim(from: 0, to: busy ? 0.3 : 1)
                .stroke(AngularGradient(colors: [c.opacity(0.1), c, c2, c], center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(spin ? 360 : 0))
                .padding(14)
                .opacity(state == .off ? 0.55 : 1)

            // Disc.
            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(
                            state == .off
                                ? AnyShapeStyle(LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                                                               startPoint: .top, endPoint: .bottom))
                                : AnyShapeStyle(LinearGradient(colors: [c, c2.opacity(0.85)],
                                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                    Circle()
                        .stroke(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.02)],
                                               startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
                    Circle()
                        .fill(RadialGradient(colors: [Color.white.opacity(0.28), .clear],
                                             center: .init(x: 0.35, y: 0.25), startRadius: 2, endRadius: 90))
                    Image(systemName: "power")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundColor(state == .off ? c : .white)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                }
                .padding(36)
                .shadow(color: c.opacity(state == .off ? 0.15 : 0.55), radius: 26, y: 10)
            }
            .buttonStyle(PressScale())
            .accessibilityLabel(state == .on ? "Отключить VPN" : "Подключить VPN")
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true }
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { spin = true }
            ripple = true
        }
        .animation(.easeInOut(duration: 0.5), value: state)
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Stats

struct StatsRow: View {
    var rx: UInt64
    var tx: UInt64
    var transport: String

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                StatTile(icon: "arrow.down", title: "Получено", value: Self.bytes(rx), tint: Palette.mint)
                StatTile(icon: "arrow.up", title: "Отправлено", value: Self.bytes(tx), tint: Palette.teal)
            }
            if !transport.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Канал: \(transport)")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Palette.text2)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Palette.card))
                .overlay(Capsule().stroke(Palette.stroke))
            }
        }
    }

    static func bytes(_ n: UInt64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f.string(fromByteCount: Int64(clamping: n))
    }
}

struct StatTile: View {
    var icon: String
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Palette.text3)
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glass(radius: 22)
    }
}

// MARK: - Error

struct ErrorCard: View {
    var text: String
    var openLog: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Palette.coral)
                Text("Что пошло не так")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(Palette.text2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Button(action: openLog) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                    Text("Открыть журнал")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Palette.coral)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Palette.coral.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Palette.coral.opacity(0.35)))
    }
}

// MARK: - Key

struct KeyCard: View {
    @EnvironmentObject var vpn: VPNController
    @Binding var showEnter: Bool
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: vpn.profile == nil
                                             ? [Color.white.opacity(0.10), Color.white.opacity(0.04)]
                                             : [Palette.indigo, Palette.violet],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: vpn.profile == nil ? "key" : "key.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(vpn.profile?.name ?? "Ключ не добавлен")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundColor(Palette.text3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if vpn.profile != nil {
                    Menu {
                        Button { showEnter = true } label: { Label("Заменить ключ", systemImage: "pencil") }
                        Button {
                            UIPasteboard.general.string = vpn.key
                            vpn.show("Ключ скопирован")
                        } label: { Label("Скопировать ключ", systemImage: "doc.on.doc") }
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Удалить ключ", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Palette.text2)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Palette.card))
                    }
                }
            }

            if let p = vpn.profile, !p.transports.isEmpty {
                FlowChips(items: p.transports)
            }

            HStack(spacing: 10) {
                Button { vpn.pasteKey() } label: {
                    Label("Вставить", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FilledButton(tint: Palette.indigo))

                Button { showEnter = true } label: {
                    Label("Ввести", systemImage: "keyboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TonalButton())
            }
        }
        .padding(18)
        .glass(radius: 28)
        .alert("Удалить ключ?", isPresented: $confirmDelete) {
            Button("Удалить", role: .destructive) { vpn.deleteKey() }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var detail: String {
        guard let p = vpn.profile else { return "Вставьте ключ openflux:// из буфера" }
        if p.mode == "stream" { return "Режим PHP-узла" }
        let n = p.transports.count
        return n == 1 ? "1 канал" : (n >= 2 && n <= 4 ? "\(n) канала" : "\(n) каналов")
    }
}

struct FlowChips: View {
    var items: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, t in
                    Text(t)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Palette.text2)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Palette.card))
                        .overlay(Capsule().stroke(Palette.stroke))
                }
            }
        }
    }
}

// MARK: - Sheets

struct EnterKeySheet: View {
    @EnvironmentObject var vpn: VPNController
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationView {
            ZStack {
                Palette.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    Text("Вставьте ключ, который выдал сервер. Он начинается с openflux://")
                        .font(.system(size: 14))
                        .foregroundColor(Palette.text2)
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("openflux://v1/…")
                                .foregroundColor(Palette.text3)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 20)
                        }
                        TextEditor(text: $text)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.white)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .padding(12)
                    }
                    .frame(minHeight: 160)
                    .glass(radius: 20)

                    Button {
                        if vpn.saveKey(text) { dismiss() }
                    } label: {
                        Text("Сохранить ключ").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FilledButton(tint: Palette.indigo))
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                }
                .padding(18)
            }
            .navigationTitle("Новый ключ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct LogSheet: View {
    @EnvironmentObject var vpn: VPNController
    @Environment(\.dismiss) private var dismiss
    @State private var log = ""

    var body: some View {
        NavigationView {
            ZStack {
                Palette.bg.ignoresSafeArea()
                ScrollView {
                    Text(log.isEmpty ? "Загрузка…" : log)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Palette.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(16)
                }
            }
            .navigationTitle("Журнал")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                    Button {
                        UIPasteboard.general.string = log
                        vpn.show("Журнал скопирован")
                    } label: { Image(systemName: "doc.on.doc") }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { reload() }
    }

    private func reload() {
        vpn.fetchLog { text in log = text }
    }
}

// MARK: - Small pieces

struct Logo: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Palette.indigo, Palette.violet],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "bolt.shield.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
        }
        .shadow(color: Palette.indigo.opacity(0.5), radius: 10, y: 4)
    }
}

struct CircleIconButton: View {
    var system: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Palette.card))
                .overlay(Circle().stroke(Palette.stroke))
        }
        .buttonStyle(PressScale())
    }
}

struct Toast: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().stroke(Palette.stroke))
            .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
            .padding(.horizontal, 24)
    }
}

struct FilledButton: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [tint, Palette.violet], startPoint: .leading, endPoint: .trailing))
            )
            .shadow(color: tint.opacity(0.4), radius: 12, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct TonalButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.vertical, 15)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.09)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.stroke))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension View {
    func glass(radius: CGFloat) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.ultraThinMaterial))
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Palette.stroke))
    }
}

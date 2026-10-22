import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var vpn: VPNController
    @EnvironmentObject var updater: Updater
    @State private var showEnter = false
    @State private var showLog = false
    @State private var confirmDelete = false

    var body: some View {
        ZStack(alignment: .bottom) {
            M3.surface.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .background(M3.surface.ignoresSafeArea(edges: .top))
                    .zIndex(1)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        HeroButton(state: vpn.state) { vpn.toggle() }
                            .frame(width: 300, height: 300)
                            .padding(.top, 12)

                        statusBlock
                            .padding(.top, 12)

                        if let r = updater.available {
                            UpdateCard(build: r.build) { updater.download() }
                                .padding(.top, 24)
                                .transition(.scale(scale: 0.94, anchor: .top).combined(with: .opacity))
                        }

                        if vpn.state == .on {
                            ConnectedGroup(rx: vpn.rx, tx: vpn.tx,
                                           transport: vpn.tunnelSilent ? "Туннель не отвечает — откройте журнал" : vpn.transport)
                                .padding(.top, 28)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity),
                                    removal: .opacity))
                        }

                        if vpn.state == .error, let err = vpn.errorText {
                            ErrorCard(text: err) { showLog = true }
                                .padding(.top, 28)
                                .transition(.scale(scale: 0.94, anchor: .top).combined(with: .opacity))
                        }

                        keySection
                            .padding(.top, 32)

                        AboutSection()
                            .padding(.top, 28)

                        Text("Hiseng VPN · GPL-3.0 · исходный код: github.com/prismexec/Hiseng-VPN-")
                            .font(.m3(.bodySmall))
                            .foregroundColor(M3.onSurfaceVariant.opacity(0.7))
                            .padding(.top, 20)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)
                }
            }

            if let t = vpn.toast {
                Snackbar(text: t)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }

            if confirmDelete {
                M3Dialog(icon: "trash", title: "Удалить ключ?",
                         text: "VPN отключится. Чтобы подключиться снова, понадобится ключ hiseng://.",
                         confirm: "Удалить", destructive: true,
                         onConfirm: { confirmDelete = false; vpn.deleteKey() },
                         onDismiss: { confirmDelete = false })
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    .zIndex(2)
            }
        }
        .animation(M3Motion.spatial, value: vpn.state)
        .animation(M3Motion.spatial, value: vpn.errorText)
        .animation(M3Motion.spatial, value: vpn.toast)
        .animation(M3Motion.effects, value: confirmDelete)
        .animation(M3Motion.spatial, value: updater.available)
        .task { await updater.check() }
        .sheet(isPresented: $showEnter) {
            EnterKeySheet().environmentObject(vpn).m3Sheet(large: true)
        }
        .sheet(isPresented: $showLog) {
            LogSheet().environmentObject(vpn).m3Sheet()
        }
    }

    // MARK: top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            ShapeIcon(system: "shield.lefthalf.filled", shape: .cookie7,
                      container: M3.primaryContainer, content: M3.onPrimaryContainer, size: 44)
            Text("Hiseng VPN")
                .font(.m3(.headlineSmall, emphasized: true))
                .foregroundColor(M3.onSurface)
            Spacer()
            Button { showLog = true } label: {
                Image(systemName: "doc.text.magnifyingglass")
            }
            .buttonStyle(M3IconButton())
            .accessibilityLabel("Журнал")
        }
        .padding(.top, 8)
    }

    // MARK: status

    private var statusBlock: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.m3(.displaySmall, emphasized: true))
                .foregroundColor(titleColor)
                .id(title)
                .transition(.asymmetric(
                    insertion: .offset(y: 12).combined(with: .opacity),
                    removal: .offset(y: -12).combined(with: .opacity)))

            if vpn.state == .on, let since = vpn.connectedSince {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(Self.elapsed(from: since, to: ctx.date))
                            .font(.m3(.labelLarge, emphasized: true).monospacedDigit())
                    }
                    .foregroundColor(M3.onTertiaryContainer)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Capsule().fill(M3.tertiaryContainer))
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                Text(subtitle)
                    .font(.m3(.bodyLarge))
                    .foregroundColor(M3.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .id(subtitle)
                    .transition(.opacity)
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
        case .on: return "Подключено"
        case .error: return "Ошибка"
        }
    }

    private var titleColor: Color {
        switch vpn.state {
        case .on: return M3.tertiary
        case .error: return M3.error
        default: return M3.onSurface
        }
    }

    private var subtitle: String {
        switch vpn.state {
        case .off: return vpn.key == nil ? "Добавьте ключ ниже" : "Нажмите, чтобы подключиться"
        case .error: return "Нажмите, чтобы попробовать снова"
        default: return vpn.message
        }
    }

    static func elapsed(from: Date, to: Date) -> String {
        let s = max(0, Int(to.timeIntervalSince(from)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    // MARK: key

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ключ доступа")
                .font(.m3(.labelLarge, emphasized: true))
                .foregroundColor(M3.primary)
                .padding(.leading, 16)
                .padding(.bottom, 10)

            let channels = vpn.profile?.transports ?? []
            VStack(spacing: 3) {
                keyItem
                    .segment(channels.isEmpty ? .single : .top)
                if !channels.isEmpty {
                    ChannelsItem(items: channels)
                        .segment(.bottom)
                }
            }

            VStack(spacing: 10) {
                Button { vpn.pasteKey() } label: {
                    Label("Вставить ключ из буфера", systemImage: "doc.on.clipboard.fill")
                }
                .buttonStyle(M3Button(.filled, height: 60))

                Button { showEnter = true } label: {
                    Label("Ввести вручную", systemImage: "keyboard")
                }
                .buttonStyle(M3Button(.tonal, height: 52))
            }
            .padding(.top, 14)
        }
    }

    private var keyItem: some View {
        let has = vpn.profile != nil
        return HStack(spacing: 16) {
            ShapeIcon(system: has ? "checkmark" : "key.fill", shape: .cookie6,
                      container: has ? M3.tertiaryContainer : M3.secondaryContainer,
                      content: has ? M3.onTertiaryContainer : M3.onSecondaryContainer,
                      size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(vpn.profile?.name ?? "Ключ не добавлен")
                    .font(.m3(.titleMedium))
                    .foregroundColor(M3.onSurface)
                    .lineLimit(1)
                Text(keyDetail)
                    .font(.m3(.bodyMedium))
                    .foregroundColor(M3.onSurfaceVariant)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if has {
                Menu {
                    Button { showEnter = true } label: { Label("Заменить ключ", systemImage: "pencil") }
                    Button {
                        UIPasteboard.general.string = vpn.displayKey
                        vpn.show("Ключ скопирован")
                    } label: { Label("Скопировать ключ", systemImage: "doc.on.doc") }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Удалить ключ", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(M3.onSurfaceVariant)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(16)
    }

    private var keyDetail: String {
        guard let p = vpn.profile else { return "Скопируйте ключ hiseng:// и вставьте" }
        if p.mode == "stream" { return "PHP-узел" }
        let n = p.transports.count
        let word = n % 10 == 1 && n % 100 != 11 ? "канал"
            : (2...4).contains(n % 10) && !(12...14).contains(n % 100) ? "канала" : "каналов"
        return "\(n) \(word) связи"
    }
}

// MARK: - Hero power button

/// Keeps the hero turning and eases its speed between states, so stopping or
/// speeding up never jumps.
/// Morphs the hero between state shapes with a spring and crossfades its
/// colour, driven by the same frame clock as the rotation.
private final class Morpher {
    struct Frame {
        var shape: ShapeProfile
        var previous: VPNState
        var colour: Double
    }

    private var from = ShapeProfile(r: [])
    private var to = ShapeProfile(r: [])
    private var start: TimeInterval = 0
    private var previous: VPNState?
    private var current: VPNState?

    func frame(state: VPNState, target: ShapeProfile, at t: TimeInterval) -> Frame {
        if current == nil {
            current = state
            previous = state
            from = target
            to = target
            start = t - 10
        } else if state != current {
            from = shape(at: t)
            previous = current
            current = state
            to = target
            start = t
        }
        let colour = min(1, max(0, (t - start) / 0.45))
        return Frame(shape: shape(at: t), previous: previous ?? state, colour: colour)
    }

    private func shape(at t: TimeInterval) -> ShapeProfile {
        let p = min(1, max(0, (t - start) / 0.75))
        // Damped spring: a little overshoot, then settles.
        let e = p >= 1 ? 1 : 1 - exp(-6 * p) * cos(9 * p)
        return from.lerp(to: to, e)
    }
}

private final class Spinner {
    private(set) var angle = 0.0
    private var speed = 0.0
    private var last: TimeInterval?

    func advance(to t: TimeInterval, target: Double) -> Double {
        let dt = last.map { min(0.1, max(0, t - $0)) } ?? 0
        last = t
        speed += (target - speed) * min(1, dt * 2.5)
        angle = (angle + speed * dt).truncatingRemainder(dividingBy: 360)
        return angle
    }
}

struct HeroButton: View {
    var state: VPNState
    var action: () -> Void
    @State private var spinner = Spinner()
    @State private var morpher = Morpher()

    private var busy: Bool {
        state == .connecting || state == .reconnecting || state == .disconnecting
    }

    private var shape: MShape {
        switch state {
        case .off: return .cookie9
        case .connecting, .reconnecting, .disconnecting: return .softBurst
        case .on: return .cookie12
        case .error: return .cookie4
        }
    }

    private static func container(_ state: VPNState) -> Color {
        switch state {
        case .off: return M3.surfaceContainerHighest
        case .connecting, .reconnecting, .disconnecting: return M3.primaryContainer
        case .on: return M3.tertiaryContainer
        case .error: return M3.errorContainer
        }
    }

    private var content: Color {
        switch state {
        case .off: return M3.primary
        case .connecting, .reconnecting, .disconnecting: return M3.onPrimaryContainer
        case .on: return M3.onTertiaryContainer
        case .error: return M3.onErrorContainer
        }
    }

    /// Degrees per second.
    private var speed: Double {
        switch state {
        case .off, .error: return 0
        case .connecting, .reconnecting, .disconnecting: return 70
        case .on: return 14
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Shape, colour and turn are all computed per frame here, so
                // the morph and the rotation never fight a SwiftUI animation.
                TimelineView(.animation) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let a = spinner.advance(to: t, target: speed)
                    let f = morpher.frame(state: state, target: shape.profile, at: t)
                    ZStack {
                        MorphShape(profile: f.shape)
                            .fill(Self.container(f.previous))
                        MorphShape(profile: f.shape)
                            .fill(Self.container(state))
                            .opacity(f.colour)
                    }
                    .rotationEffect(.degrees(a))
                }

                ZStack {
                    if busy {
                        LoadingIndicator(color: content)
                            .frame(width: 88, height: 88)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    } else {
                        Image(systemName: "power")
                            .font(.system(size: 72, weight: .semibold))
                            .foregroundColor(content)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .animation(M3Motion.spatial, value: busy)
                .animation(M3Motion.effects, value: state)
            }
            .frame(width: 236, height: 236)
            .contentShape(Circle())
        }
        .buttonStyle(BouncyPress())
        .accessibilityLabel(state == .on ? "Отключить VPN" : "Подключить VPN")
    }
}

// MARK: - Connected

struct ConnectedGroup: View {
    var rx: UInt64
    var tx: UInt64
    var transport: String

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                StatTile(icon: "arrow.down", label: "Получено", value: Self.bytes(rx), shape: .cookie4)
                    .segment(.topLeft)
                StatTile(icon: "arrow.up", label: "Отправлено", value: Self.bytes(tx), shape: .clover4)
                    .segment(.topRight)
            }
            HStack(spacing: 14) {
                ShapeIcon(system: "antenna.radiowaves.left.and.right", shape: .sunny,
                          container: M3.secondaryContainer, content: M3.onSecondaryContainer, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Канал связи")
                        .font(.m3(.bodySmall))
                        .foregroundColor(M3.onSurfaceVariant)
                    Text(transport.isEmpty ? "Определяется…" : transport)
                        .font(.m3(.titleMedium))
                        .foregroundColor(M3.onSurface)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .segment(.bottom)
        }
    }

    static func bytes(_ n: UInt64) -> String {
        let v = Double(n)
        if v < 1024 { return "\(n) Б" }
        if v < 1024 * 1024 { return String(format: "%.0f КБ", v / 1024) }
        if v < 1024 * 1024 * 1024 { return String(format: "%.1f МБ", v / 1_048_576) }
        return String(format: "%.2f ГБ", v / 1_073_741_824)
    }
}

struct StatTile: View {
    var icon: String
    var label: String
    var value: String
    var shape: MShape

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShapeIcon(system: icon, shape: shape, container: M3.tertiaryContainer,
                      content: M3.onTertiaryContainer, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.m3(.titleLarge, emphasized: true).monospacedDigit())
                    .foregroundColor(M3.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.m3(.bodySmall))
                    .foregroundColor(M3.onSurfaceVariant)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChannelsItem: View {
    var items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Каналы")
                .font(.m3(.labelMedium))
                .foregroundColor(M3.onSurfaceVariant)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, t in
                        Text(t)
                            .font(.m3(.labelLarge))
                            .foregroundColor(M3.onSurfaceVariant)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(M3.outlineVariant, lineWidth: 1))
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Error

struct ErrorCard: View {
    var text: String
    var openLog: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ShapeIcon(system: "exclamationmark", shape: .cookie4,
                          container: M3.error, content: M3.onError, size: 44)
                Text("Не удалось подключиться")
                    .font(.m3(.titleMedium, emphasized: true))
                    .foregroundColor(M3.onErrorContainer)
            }
            Text(text)
                .font(.m3(.bodyMedium))
                .foregroundColor(M3.onErrorContainer)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Button(action: openLog) {
                Label("Открыть журнал", systemImage: "doc.text")
            }
            .buttonStyle(M3Button(.error, height: 44, fill: false))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(M3.errorContainer))
    }
}

// MARK: - Sheets

struct EnterKeySheet: View {
    @EnvironmentObject var vpn: VPNController
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DragHandle()
            Text("Новый ключ")
                .font(.m3(.headlineSmall))
                .foregroundColor(M3.onSurface)
            Text("Вставьте ключ hiseng:// (или openflux://), который выдал сервер")
                .font(.m3(.bodyMedium))
                .foregroundColor(M3.onSurfaceVariant)
                .padding(.top, 6)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(M3.onSurface)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .focused($focused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .frame(height: 150)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(focused ? M3.primary : M3.outline, lineWidth: focused ? 2 : 1))
                Text("Ключ")
                    .font(.m3(.bodySmall))
                    .foregroundColor(focused ? M3.primary : M3.onSurfaceVariant)
                    .padding(.horizontal, 4)
                    .background(M3.surfaceContainerLow)
                    .offset(x: 12, y: -8)
            }
            .padding(.top, 22)
            .animation(M3Motion.effects, value: focused)

            Button {
                text = UIPasteboard.general.string ?? text
            } label: {
                Label("Из буфера обмена", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(M3Button(.outlined, height: 40, fill: false))
            .padding(.top, 12)

            HStack(spacing: 8) {
                Button("Отмена") { dismiss() }
                    .buttonStyle(M3Button(.text, height: 48, fill: false))
                Spacer()
                Button("Сохранить") {
                    if vpn.saveKey(text) { dismiss() }
                }
                .buttonStyle(M3Button(.filled, height: 48, fill: false))
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 24)
            Spacer()
        }
        .padding(.horizontal, 24)
        .background(M3.surfaceContainerLow.ignoresSafeArea())
        .onAppear {
            text = vpn.displayKey ?? ""
            focused = true
        }
    }
}

struct LogSheet: View {
    @EnvironmentObject var vpn: VPNController
    @State private var log = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DragHandle()
            HStack {
                Text("Журнал")
                    .font(.m3(.headlineSmall))
                    .foregroundColor(M3.onSurface)
                Spacer()
                Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(M3IconButton(tonal: false, size: 44))
                Button {
                    UIPasteboard.general.string = log
                    vpn.show("Журнал скопирован")
                } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(M3IconButton(size: 44))
            }
            ScrollView {
                Text(log.isEmpty ? "Загрузка…" : log)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(M3.onSurfaceVariant)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(16)
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(M3.surfaceContainerHighest))
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 20)
        .background(M3.surfaceContainerLow.ignoresSafeArea())
        .onAppear { reload() }
    }

    private func reload() {
        vpn.fetchLog { text in log = text }
    }
}

// MARK: - Updates

struct UpdateCard: View {
    var build: Int
    var download: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ShapeIcon(system: "arrow.down", shape: .sunny,
                          container: M3.primary, content: M3.onPrimary, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Доступно обновление")
                        .font(.m3(.titleMedium, emphasized: true))
                        .foregroundColor(M3.onPrimaryContainer)
                    Text("Сборка \(build) · у вас \(Updater.currentBuild)")
                        .font(.m3(.bodyMedium))
                        .foregroundColor(M3.onPrimaryContainer.opacity(0.8))
                }
            }
            Text("Скачайте IPA и откройте её в программе, которой вы подписываете приложения. Если добавить источник обновлений (ниже), новые версии будут появляться прямо там.")
                .font(.m3(.bodyMedium))
                .foregroundColor(M3.onPrimaryContainer)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: download) {
                Label("Скачать обновление", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(M3Button(.filled, height: 52))
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(M3.primaryContainer))
    }
}

struct AboutSection: View {
    @EnvironmentObject var vpn: VPNController
    @EnvironmentObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("О приложении")
                .font(.m3(.labelLarge, emphasized: true))
                .foregroundColor(M3.primary)
                .padding(.leading, 16)
                .padding(.bottom, 10)
            VStack(spacing: 3) {
                HStack(spacing: 16) {
                    ShapeIcon(system: "info", shape: .cookie7, container: M3.secondaryContainer,
                              content: M3.onSecondaryContainer, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Версия")
                            .font(.m3(.titleMedium))
                            .foregroundColor(M3.onSurface)
                        Text(Updater.versionText)
                            .font(.m3(.bodyMedium))
                            .foregroundColor(M3.onSurfaceVariant)
                    }
                    Spacer(minLength: 0)
                    Button {
                        Task {
                            if let msg = await updater.check(manual: true) { vpn.show(msg) }
                        }
                    } label: {
                        if updater.checking {
                            LoadingIndicator(color: M3.onSecondaryContainer).frame(width: 22, height: 22)
                        } else {
                            Text("Проверить")
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .buttonStyle(M3Button(.tonal, height: 40, fill: false))
                }
                .padding(16)
                .segment(.top)

                HStack(spacing: 16) {
                    ShapeIcon(system: "square.stack.3d.down.right", shape: .clover4, container: M3.tertiaryContainer,
                              content: M3.onTertiaryContainer, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Источник обновлений")
                            .font(.m3(.titleMedium))
                            .foregroundColor(M3.onSurface)
                        Text("Добавьте в ESign, Feather или AltStore — обновления будут приходить туда")
                            .font(.m3(.bodyMedium))
                            .foregroundColor(M3.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button {
                        UIPasteboard.general.string = Updater.sourceURL
                        vpn.show("Ссылка на источник скопирована")
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(M3IconButton(size: 44))
                }
                .padding(16)
                .segment(.bottom)
            }
        }
    }
}

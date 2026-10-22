import SwiftUI
import UIKit

// Material 3 Expressive for SwiftUI: the colour scheme, type scale, motion,
// morphing shapes and the components the screen is built from.

// MARK: - Colour scheme

/// Baseline M3 scheme (seed #6750A4) with a green tertiary for "connected",
/// the same palette as the Android app. Follows the system light/dark mode.
enum M3 {
    static let primary = dyn(0x6750A4, 0xD0BCFF)
    static let onPrimary = dyn(0xFFFFFF, 0x381E72)
    static let primaryContainer = dyn(0xEADDFF, 0x4F378B)
    static let onPrimaryContainer = dyn(0x21005D, 0xEADDFF)
    static let secondary = dyn(0x625B71, 0xCCC2DC)
    static let secondaryContainer = dyn(0xE8DEF8, 0x4A4458)
    static let onSecondaryContainer = dyn(0x1D192B, 0xE8DEF8)
    static let tertiary = dyn(0x006B54, 0x7FD8BE)
    static let onTertiary = dyn(0xFFFFFF, 0x00382B)
    static let tertiaryContainer = dyn(0x9CF5D9, 0x00513F)
    static let onTertiaryContainer = dyn(0x002118, 0x9CF5D9)
    static let error = dyn(0xB3261E, 0xF2B8B5)
    static let onError = dyn(0xFFFFFF, 0x601410)
    static let errorContainer = dyn(0xF9DEDC, 0x8C1D18)
    static let onErrorContainer = dyn(0x410E0B, 0xF9DEDC)
    static let surface = dyn(0xFEF7FF, 0x141218)
    static let onSurface = dyn(0x1D1B20, 0xE6E0E9)
    static let onSurfaceVariant = dyn(0x49454F, 0xCAC4D0)
    static let outline = dyn(0x79747E, 0x938F99)
    static let outlineVariant = dyn(0xCAC4D0, 0x49454F)
    static let surfaceContainerLowest = dyn(0xFFFFFF, 0x0F0D13)
    static let surfaceContainerLow = dyn(0xF7F2FA, 0x1D1B20)
    static let surfaceContainer = dyn(0xF3EDF7, 0x211F26)
    static let surfaceContainerHigh = dyn(0xECE6F0, 0x2B2930)
    static let surfaceContainerHighest = dyn(0xE6E0E9, 0x36343B)
    static let inverseSurface = dyn(0x322F35, 0xE6E0E9)
    static let inverseOnSurface = dyn(0xF5EFF7, 0x322F35)

    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Type scale

enum M3Type {
    case displayLarge, displayMedium, displaySmall
    case headlineLarge, headlineMedium, headlineSmall
    case titleLarge, titleMedium, titleSmall
    case bodyLarge, bodyMedium, bodySmall
    case labelLarge, labelMedium, labelSmall
}

extension Font {
    /// M3 type scale; `emphasized` is the Expressive heavier variant.
    static func m3(_ t: M3Type, emphasized e: Bool = false) -> Font {
        switch t {
        case .displayLarge: return .system(size: 57, weight: e ? .bold : .regular, design: .rounded)
        case .displayMedium: return .system(size: 45, weight: e ? .bold : .regular, design: .rounded)
        case .displaySmall: return .system(size: 36, weight: e ? .bold : .regular, design: .rounded)
        case .headlineLarge: return .system(size: 32, weight: e ? .bold : .regular, design: .rounded)
        case .headlineMedium: return .system(size: 28, weight: e ? .bold : .regular, design: .rounded)
        case .headlineSmall: return .system(size: 24, weight: e ? .bold : .regular, design: .rounded)
        case .titleLarge: return .system(size: 22, weight: e ? .bold : .medium, design: .rounded)
        case .titleMedium: return .system(size: 16, weight: e ? .bold : .semibold)
        case .titleSmall: return .system(size: 14, weight: e ? .bold : .semibold)
        case .bodyLarge: return .system(size: 16, weight: e ? .medium : .regular)
        case .bodyMedium: return .system(size: 14, weight: e ? .medium : .regular)
        case .bodySmall: return .system(size: 12, weight: e ? .medium : .regular)
        case .labelLarge: return .system(size: 14, weight: e ? .bold : .semibold)
        case .labelMedium: return .system(size: 12, weight: e ? .bold : .semibold)
        case .labelSmall: return .system(size: 11, weight: e ? .bold : .semibold)
        }
    }
}

// MARK: - Motion

/// Expressive motion scheme: bouncy springs for movement and shape,
/// critically damped ones for colour and opacity.
enum M3Motion {
    static let spatialFast = Animation.spring(response: 0.3, dampingFraction: 0.6)
    static let spatial = Animation.spring(response: 0.5, dampingFraction: 0.68)
    static let spatialSlow = Animation.spring(response: 0.7, dampingFraction: 0.7)
    static let effects = Animation.spring(response: 0.35, dampingFraction: 1)
}

// MARK: - Morphing shapes

/// A closed outline as its radius sampled at fixed angles, so any two shapes
/// morph into each other (SwiftUI animates the samples).
struct ShapeProfile: VectorArithmetic {
    static let count = 192
    var r: [Double]

    static var zero: ShapeProfile { ShapeProfile(r: []) }

    static func + (a: ShapeProfile, b: ShapeProfile) -> ShapeProfile { combine(a, b, +) }
    static func - (a: ShapeProfile, b: ShapeProfile) -> ShapeProfile { combine(a, b, -) }

    private static func combine(_ a: ShapeProfile, _ b: ShapeProfile,
                                _ op: (Double, Double) -> Double) -> ShapeProfile {
        let n = max(a.r.count, b.r.count)
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            out[i] = op(i < a.r.count ? a.r[i] : 0, i < b.r.count ? b.r[i] : 0)
        }
        return ShapeProfile(r: out)
    }

    mutating func scale(by rhs: Double) {
        for i in r.indices { r[i] *= rhs }
    }

    var magnitudeSquared: Double { r.reduce(0) { $0 + $1 * $1 } }

    func lerp(to b: ShapeProfile, _ t: Double) -> ShapeProfile {
        guard r.count == b.r.count else { return b }
        var out = r
        for i in out.indices { out[i] += (b.r[i] - out[i]) * t }
        return ShapeProfile(r: out)
    }
}

/// The M3 Expressive shape library, as polar outlines.
enum MShape: CaseIterable, Hashable {
    case circle, square, oval, pill, pentagon
    case cookie4, cookie6, cookie7, cookie9, cookie12
    case softBurst, sunny, verySunny, clover4, flower

    var profile: ShapeProfile { MShape.cache[self] ?? ShapeProfile(r: []) }

    private static let cache: [MShape: ShapeProfile] =
        Dictionary(uniqueKeysWithValues: MShape.allCases.map { ($0, $0.compute()) })

    private func compute() -> ShapeProfile {
        let n = ShapeProfile.count
        var r = [Double](repeating: 1, count: n)
        var extent = 0.0
        for i in 0..<n {
            let th = 2 * Double.pi * Double(i) / Double(n)
            r[i] = radius(th)
            extent = max(extent, abs(r[i] * cos(th)), abs(r[i] * sin(th)))
        }
        // Fit the bounding box, so every shape fills its frame the same way.
        if extent > 0 { for i in 0..<n { r[i] /= extent } }
        return ShapeProfile(r: r)
    }

    private func radius(_ th: Double) -> Double {
        let up = -Double.pi / 2
        switch self {
        case .circle: return 1
        case .square: return Self.superellipse(th, 1, 1, 4)
        case .oval: return Self.superellipse(th, 1, 0.78, 2)
        case .pill: return Self.superellipse(th, 1, 0.58, 3.2)
        case .pentagon: return Self.scallop(th, 5, 0.12, 2.8, up)
        case .cookie4: return Self.scallop(th, 4, 0.14, 1.6, .pi / 4)
        case .cookie6: return Self.scallop(th, 6, 0.11, 1.5, up)
        case .cookie7: return Self.scallop(th, 7, 0.10, 1.5, up)
        case .cookie9: return Self.scallop(th, 9, 0.085, 1.5, up)
        case .cookie12: return Self.scallop(th, 12, 0.065, 1.5, up)
        case .softBurst: return Self.burst(th, 10, 0.16, 1.15, up)
        case .sunny: return Self.burst(th, 8, 0.12, 1.25, up)
        case .verySunny: return Self.burst(th, 8, 0.2, 1.0, up)
        case .clover4: return Self.scallop(th, 4, 0.38, 0.75, .pi / 4)
        case .flower: return Self.scallop(th, 8, 0.24, 0.9, up)
        }
    }

    /// Round lobes, tighter valleys (cookies, clovers).
    private static func scallop(_ th: Double, _ k: Double, _ d: Double, _ q: Double, _ off: Double) -> Double {
        1 - d * (1 - pow(abs(cos(k * (th - off) / 2)), q))
    }

    /// Pointed tips, round valleys (bursts, suns).
    private static func burst(_ th: Double, _ k: Double, _ d: Double, _ p: Double, _ off: Double) -> Double {
        1 - d * pow(abs(sin(k * (th - off) / 2)), p)
    }

    private static func superellipse(_ th: Double, _ a: Double, _ b: Double, _ n: Double) -> Double {
        let c = abs(cos(th)) / a, s = abs(sin(th)) / b
        return pow(pow(c, n) + pow(s, n), -1 / n)
    }
}

/// Draws a ShapeProfile; changing the profile with an animation morphs it.
struct MorphShape: Shape {
    var profile: ShapeProfile

    init(_ shape: MShape) { profile = shape.profile }
    init(profile: ShapeProfile) { self.profile = profile }

    var animatableData: ShapeProfile {
        get { profile }
        set { profile = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = profile.r
        let n = r.count
        guard n > 2 else { return Path(ellipseIn: rect) }
        let cx = rect.midX, cy = rect.midY
        let s = Double(min(rect.width, rect.height) / 2)
        func pt(_ i: Int) -> CGPoint {
            let j = (i % n + n) % n
            let th = 2 * Double.pi * Double(j) / Double(n)
            return CGPoint(x: cx + CGFloat(r[j] * cos(th) * s), y: cy + CGFloat(r[j] * sin(th) * s))
        }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        var p = Path()
        p.move(to: mid(pt(n - 1), pt(0)))
        for i in 0..<n {
            p.addQuadCurve(to: mid(pt(i), pt(i + 1)), control: pt(i))
        }
        p.closeSubpath()
        return p
    }
}

/// Rectangle with its own radius per corner (M3 segmented lists and
/// connected button groups; UnevenRoundedRectangle needs iOS 17).
struct CornerShape: Shape {
    var tl: CGFloat, tr: CGFloat, br: CGFloat, bl: CGFloat

    func path(in r: CGRect) -> Path {
        let m = min(r.width, r.height) / 2
        let tl = min(self.tl, m), tr = min(self.tr, m), br = min(self.br, m), bl = min(self.bl, m)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + tl, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + tr), radius: tr)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - br, y: r.maxY), radius: br)
        p.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - bl), radius: bl)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + tl))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + tl, y: r.minY), radius: tl)
        p.closeSubpath()
        return p
    }
}

/// Where an item sits in a segmented group: outer corners large, inner small.
enum Segment {
    case single, top, middle, bottom, topLeft, topRight

    var shape: CornerShape {
        let L: CGFloat = 28, S: CGFloat = 6
        switch self {
        case .single: return CornerShape(tl: L, tr: L, br: L, bl: L)
        case .top: return CornerShape(tl: L, tr: L, br: S, bl: S)
        case .middle: return CornerShape(tl: S, tr: S, br: S, bl: S)
        case .bottom: return CornerShape(tl: S, tr: S, br: L, bl: L)
        case .topLeft: return CornerShape(tl: L, tr: S, br: S, bl: S)
        case .topRight: return CornerShape(tl: S, tr: L, br: S, bl: S)
        }
    }
}

extension View {
    func segment(_ s: Segment, _ color: Color = M3.surfaceContainer) -> some View {
        background(s.shape.fill(color))
    }

    /// Bottom sheet look: own drag handle, 28 pt corners, surfaceContainerLow.
    func m3Sheet(large: Bool = false) -> some View {
        modifier(M3SheetStyle(large: large))
    }
}

private struct M3SheetStyle: ViewModifier {
    var large: Bool

    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content
                .presentationDetents(large ? [.large] : [.medium, .large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
                .presentationBackground(M3.surfaceContainerLow)
        } else if #available(iOS 16.0, *) {
            content
                .presentationDetents(large ? [.large] : [.medium, .large])
                .presentationDragIndicator(.hidden)
        } else {
            content
        }
    }
}

// MARK: - Loading indicator

/// M3 Expressive LoadingIndicator: one shape morphing through the sequence
/// while it turns.
struct LoadingIndicator: View {
    var color: Color

    private static let sequence: [ShapeProfile] =
        [MShape.softBurst, .cookie9, .pentagon, .pill, .sunny, .cookie4, .oval].map { $0.profile }

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let k = t / 0.65
            let step = floor(k)
            let n = Self.sequence.count
            let i = Int(step.truncatingRemainder(dividingBy: Double(n)))
            let e = Self.ease(min(1, (k - step) / 0.75))
            let shape = Self.sequence[i].lerp(to: Self.sequence[(i + 1) % n], e)
            let angle = (t * 110 + (step + e) * 45).truncatingRemainder(dividingBy: 360)
            MorphShape(profile: shape)
                .fill(color)
                .rotationEffect(.degrees(angle))
        }
    }

    /// Ease-out with a little overshoot, like the spring the spec uses.
    private static func ease(_ x: Double) -> Double {
        let c1 = 1.3, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }
}

// MARK: - Buttons

/// M3 Expressive button: a pill that squares its corners while pressed.
struct M3Button: ButtonStyle {
    enum Kind { case filled, tonal, outlined, text, error, tertiary }
    var kind: Kind
    var height: CGFloat
    var fill: Bool

    init(_ kind: Kind, height: CGFloat = 56, fill: Bool = true) {
        self.kind = kind
        self.height = height
        self.fill = fill
    }

    func makeBody(configuration: Configuration) -> some View {
        M3ButtonBody(configuration: configuration, kind: kind, height: height, fill: fill)
    }
}

private struct M3ButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: M3Button.Kind
    let height: CGFloat
    let fill: Bool
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: pressed ? min(16, height / 3.5) : height / 2, style: .continuous)
        configuration.label
            .font(.m3(height >= 56 ? .titleMedium : .labelLarge, emphasized: true))
            .foregroundColor(enabled ? fg : M3.onSurface.opacity(0.38))
            .padding(.horizontal, kind == .text ? 14 : 24)
            .frame(maxWidth: fill ? .infinity : nil, minHeight: height)
            .background(shape.fill(enabled ? bg : (kind == .text ? Color.clear : M3.onSurface.opacity(0.12))))
            .overlay(shape.stroke(kind == .outlined ? M3.outlineVariant : Color.clear, lineWidth: 1))
            .overlay(shape.fill(fg.opacity(pressed ? 0.10 : 0)))
            .contentShape(shape)
            .animation(M3Motion.spatialFast, value: pressed)
    }

    private var bg: Color {
        switch kind {
        case .filled: return M3.primary
        case .tonal: return M3.secondaryContainer
        case .outlined, .text: return .clear
        case .error: return M3.error
        case .tertiary: return M3.tertiary
        }
    }

    private var fg: Color {
        switch kind {
        case .filled: return M3.onPrimary
        case .tonal: return M3.onSecondaryContainer
        case .outlined, .text: return M3.primary
        case .error: return M3.onError
        case .tertiary: return M3.onTertiary
        }
    }
}

/// Icon button (standard or filled tonal) that morphs circle -> square.
struct M3IconButton: ButtonStyle {
    var tonal = true
    var size: CGFloat = 48

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: pressed ? size / 4 : size / 2, style: .continuous)
        return configuration.label
            .font(.system(size: 20, weight: .semibold))
            .foregroundColor(tonal ? M3.onSecondaryContainer : M3.onSurfaceVariant)
            .frame(width: size, height: size)
            .background(shape.fill(tonal ? M3.secondaryContainer : Color.clear))
            .overlay(shape.fill(M3.onSurface.opacity(pressed ? 0.10 : 0)))
            .contentShape(shape)
            .animation(M3Motion.spatialFast, value: pressed)
    }
}

/// Whole-shape press: shrinks with a bounce.
struct BouncyPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.45), value: configuration.isPressed)
    }
}

// MARK: - Small components

/// An icon inside a morph shape (M3 Expressive avatar / leading element).
struct ShapeIcon: View {
    var system: String
    var shape: MShape
    var container: Color
    var content: Color
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            MorphShape(shape).fill(container)
            Image(systemName: system)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundColor(content)
        }
        .frame(width: size, height: size)
    }
}

struct DragHandle: View {
    var body: some View {
        Capsule()
            .fill(M3.onSurfaceVariant.opacity(0.4))
            .frame(width: 32, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            .padding(.bottom, 10)
    }
}

struct Snackbar: View {
    var text: String

    var body: some View {
        HStack {
            Text(text)
                .font(.m3(.bodyMedium))
                .foregroundColor(M3.inverseOnSurface)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 48)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(M3.inverseSurface))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}

/// Basic M3 dialog with a hero icon.
struct M3Dialog: View {
    var icon: String
    var title: String
    var text: String
    var confirm: String
    var destructive = false
    var onConfirm: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(destructive ? M3.error : M3.secondary)
                Text(title)
                    .font(.m3(.headlineSmall))
                    .foregroundColor(M3.onSurface)
                    .multilineTextAlignment(.center)
                Text(text)
                    .font(.m3(.bodyMedium))
                    .foregroundColor(M3.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Spacer()
                    Button("Отмена", action: onDismiss)
                        .buttonStyle(M3Button(.text, height: 40, fill: false))
                    Button(confirm, action: onConfirm)
                        .buttonStyle(M3Button(destructive ? .error : .filled, height: 40, fill: false))
                }
                .padding(.top, 8)
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(M3.surfaceContainerHigh))
            .padding(24)
        }
    }
}

import SwiftUI
import UIKit

// MARK: - Glass Palette

struct GlassPalette {
    let isWhite: Bool

    var accent: Color { isWhite ? Color(hex: 0x16A34A) : Color(hex: 0x5BF277) }
    var fg: Color { isWhite ? Color(hex: 0x0B0B12) : .white }
    var subtle: Color { isWhite ? Color(hex: 0x0B0B12, alpha: 0.60) : Color.white.opacity(0.65) }
    var danger: Color { Color(hex: 0xFF6B7A) }
    var success: Color { accent }
    var bg: Color { isWhite ? Color(hex: 0xE3EEE6) : .black }
    var cardTop: Color { isWhite ? Color.white.opacity(0.42) : Color.white.opacity(0.08) }
    var cardBottom: Color { isWhite ? Color.white.opacity(0.16) : Color.white.opacity(0.025) }
}

// MARK: - Liquid Background

struct LiquidBackground<Content: View>: View {
    let isWhite: Bool
    let content: Content

    init(isWhite: Bool, @ViewBuilder content: () -> Content) {
        self.isWhite = isWhite
        self.content = content()
    }

    var body: some View {
        ZStack {
            GlassPalette(isWhite: isWhite).bg
                .ignoresSafeArea()

            WavesView(isWhite: isWhite)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            content
        }
    }
}

private struct WavesView: View {
    let isWhite: Bool
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                WaveShape(phase: phase, index: i)
                    .stroke(waveColor(for: i), lineWidth: [2.5, 2.0, 1.5, 1.2, 1.0][i])
                    .blur(radius: [8, 6, 4, 3, 2][i])
            }
        }
        .drawingGroup()
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                phase = 2 * .pi
            }
        }
    }

    private func waveColor(for index: Int) -> Color {
        let base = isWhite ? Color(hex: 0x22C55E) : Color(hex: 0x1ADC32)
        return base.opacity([0.15, 0.12, 0.10, 0.08, 0.06][index])
    }
}

private struct WaveShape: Shape {
    var phase: CGFloat
    let index: Int

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.height * (0.3 + CGFloat(index) * 0.15)
        let amplitude: CGFloat = 30 + CGFloat(index) * 10
        let frequency: CGFloat = 0.008 + CGFloat(index) * 0.002

        path.move(to: CGPoint(x: 0, y: midY))
        for x in stride(from: CGFloat(0), through: rect.width, by: 4) {
            let y = midY + amplitude * sin(frequency * x + phase + CGFloat(index))
            path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}

// MARK: - Press style (replaces onLongPressGesture hacks that swallowed taps)

struct GlassPressStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.easeOut(duration: 0.11), value: configuration.isPressed)
    }
}

// MARK: - Glass Card

struct GlassCard<Content: View>: View {
    let isWhite: Bool
    var radius: CGFloat
    var blur: CGFloat
    var tint: Color?
    var padding: EdgeInsets
    let content: Content

    init(
        isWhite: Bool,
        radius: CGFloat = 28,
        blur: CGFloat = 10,
        tint: Color? = nil,
        padding: EdgeInsets = EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18),
        @ViewBuilder content: () -> Content
    ) {
        self.isWhite = isWhite
        self.radius = radius
        self.blur = blur
        self.tint = tint
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        let palette = GlassPalette(isWhite: isWhite)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        content
            .padding(padding)
            .background {
                ZStack {
                    shape.fill(
                        LinearGradient(
                            colors: [palette.cardTop, palette.cardBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    if blur > 0 {
                        shape.fill(.ultraThinMaterial)
                    }
                    if let tint = tint {
                        shape.fill(tint.opacity(0.16))
                    }
                }
            }
            .overlay {
                GlassRim(radius: radius, isWhite: isWhite)
                    .allowsHitTesting(false)
            }
            .clipShape(shape)
            .shadow(
                color: (isWhite ? Color(hex: 0x0E3B1C) : Color.black).opacity(isWhite ? 0.18 : 0.55),
                radius: radius > 80 ? 14 : 9,
                y: radius > 80 ? 8 : 5
            )
    }
}

private struct GlassRim: View {
    let radius: CGFloat
    let isWhite: Bool

    var body: some View {
        let palette = GlassPalette(isWhite: isWhite)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        ZStack {
            // Iridescent tint
            shape.fill(
                LinearGradient(
                    colors: [
                        palette.accent.opacity(isWhite ? 0.12 : 0.14),
                        Color.clear,
                        palette.accent.opacity(isWhite ? 0.08 : 0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            // Top gloss
            shape.fill(
                LinearGradient(
                    colors: [Color.white.opacity(isWhite ? 0.45 : 0.14), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
            )

            // Rim
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        (isWhite ? Color.white : Color(hex: 0xE4FFE8)).opacity(isWhite ? 1.0 : 0.75),
                        Color.white.opacity(0.08),
                        Color.clear,
                        palette.accent.opacity(isWhite ? 0.85 : 0.50)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.2
            )
        }
    }
}

// MARK: - Glass Button

struct GlassButton: View {
    let label: String
    var icon: Image? = nil
    let isWhite: Bool
    var active: Bool = false
    var danger: Bool = false
    var expand: Bool = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let palette = GlassPalette(isWhite: isWhite)
        let tintColor: Color? = danger ? palette.danger : (active ? palette.accent : nil)
        let textColor: Color = danger ? palette.danger : (active ? palette.accent : palette.fg)

        Button {
            HapticManager.impact(.light)
            action()
        } label: {
            GlassCard(
                isWhite: isWhite,
                radius: 999,
                blur: 10,
                tint: tintColor,
                padding: EdgeInsets(top: 14, leading: 22, bottom: 14, trailing: 22)
            ) {
                HStack(spacing: 8) {
                    if let icon = icon {
                        icon
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(textColor)
                    }
                    Text(label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                }
                .frame(maxWidth: expand ? .infinity : nil)
            }
        }
        .buttonStyle(GlassPressStyle())
        .opacity(isEnabled ? 1.0 : 0.45)
    }
}

// MARK: - Glass Icon Button

struct GlassIconButton: View {
    let icon: Image
    let isWhite: Bool
    var danger: Bool = false
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        let palette = GlassPalette(isWhite: isWhite)

        Button {
            HapticManager.impact(.light)
            action()
        } label: {
            GlassCard(
                isWhite: isWhite,
                radius: 999,
                blur: 0,
                tint: danger ? palette.danger : nil,
                padding: .init()
            ) {
                icon
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(danger ? palette.danger : palette.fg)
                    .frame(width: size, height: size)
            }
        }
        .buttonStyle(GlassPressStyle(scale: 0.92))
    }
}

// MARK: - Glass Chip

struct GlassChip: View {
    let label: String
    var icon: Image? = nil
    let isWhite: Bool
    var selected: Bool = false
    var mono: Bool = false
    let action: () -> Void

    var body: some View {
        let palette = GlassPalette(isWhite: isWhite)
        let color = selected ? palette.accent : palette.fg

        Button {
            HapticManager.impact(.light)
            action()
        } label: {
            GlassCard(
                isWhite: isWhite,
                radius: 999,
                blur: 0,
                tint: selected ? palette.accent : nil,
                padding: EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15)
            ) {
                HStack(spacing: 6) {
                    if let icon = icon {
                        icon
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(color)
                    }
                    Text(label)
                        .font(.system(size: 13, weight: .semibold, design: mono ? .monospaced : .default))
                        .foregroundStyle(color)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(GlassPressStyle())
    }
}

// MARK: - Glass TextField

struct GlassTextField: View {
    @Binding var text: String
    let isWhite: Bool
    var placeholder: String = ""
    var keyboardType: UIKeyboardType = .default
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        let palette = GlassPalette(isWhite: isWhite)

        GlassCard(
            isWhite: isWhite,
            radius: 999,
            blur: 8,
            padding: EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)
        ) {
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 16))
                .foregroundStyle(palette.fg)
                .tint(palette.accent)
                .submitLabel(.done)
                .onSubmit { onSubmit?() }
        }
    }
}

// MARK: - Glass Label

struct GlassLabel: View {
    let text: String
    let isWhite: Bool

    init(_ text: String, isWhite: Bool) {
        self.text = text
        self.isWhite = isWhite
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(GlassPalette(isWhite: isWhite).subtle)
    }
}

// MARK: - Glass Progress Bar

struct GlassProgressBar: View {
    let value: Double
    let isWhite: Bool
    var color: Color?
    var height: CGFloat = 10

    var body: some View {
        let palette = GlassPalette(isWhite: isWhite)
        let c = color ?? palette.accent
        let v = value.clamped(to: 0...1)

        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.fg.opacity(0.10))
                Capsule()
                    .fill(LinearGradient(colors: [c.opacity(0.55), c], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(geo.size.width * v, v > 0 ? height : 0))
                    .shadow(color: c.opacity(0.55), radius: 10)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.18), value: value)
    }
}

// MARK: - Haptics

enum HapticManager {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - Helpers

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

import SwiftUI

// MARK: - Glass Palette
struct GlassPalette {
    let isWhite: Bool
    
    var accent: Color { isWhite ? Color(hex: 0x16A34A) : Color(hex: 0x5BF277) }
    var fg: Color { isWhite ? Color(hex: 0x0B0B12) : .white }
    var subtle: Color { isWhite ? Color(hex: 0x990B0B12) : Color(hex: 0xA6FFFFFF) }
    var danger: Color { Color(hex: 0xFF6B7A) }
    var success: Color { isWhite ? Color(hex: 0x16A34A) : Color(hex: 0x5BF277) }
    var bg: Color { isWhite ? Color(hex: 0xEEF2FA) : Color(hex: 0x000000) }
    var cardTop: Color { isWhite ? .white.opacity(0.42) : .white.opacity(0.08) }
    var cardBottom: Color { isWhite ? .white.opacity(0.16) : .white.opacity(0.025) }
}

// MARK: - Liquid Background
struct LiquidBackground: View {
    let isWhite: Bool
    let content: () -> AnyView
    
    init(isWhite: Bool, @ViewBuilder content: @escaping () -> some View) {
        self.isWhite = isWhite
        self.content = { AnyView(content()) }
    }
    
    var body: some View {
        ZStack {
            (isWhite ? Color(hex: 0xE3EEE6) : .black)
                .ignoresSafeArea()
            
            WavesView(isWhite: isWhite)
                .ignoresSafeArea()
            
            content()
        }
    }
}

private struct WavesView: View {
    let isWhite: Bool
    @State private var phase: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<5) { i in
                    WaveShape(phase: phase, index: i, isWhite: isWhite)
                        .stroke(waveColor(for: i), lineWidth: waveWidth(for: i))
                        .blur(radius: waveBlur(for: i))
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                    phase = 2 * .pi
                }
            }
        }
    }
    
    private func waveColor(for index: Int) -> Color {
        let base = isWhite ? Color(hex: 0x22C55E) : Color(hex: 0x1ADC32)
        return base.opacity([0.15, 0.12, 0.10, 0.08, 0.06][index])
    }
    
    private func waveWidth(for index: Int) -> CGFloat {
        [2.5, 2.0, 1.5, 1.2, 1.0][index]
    }
    
    private func waveBlur(for index: Int) -> CGFloat {
        [8, 6, 4, 3, 2][index]
    }
}

private struct WaveShape: Shape {
    let phase: CGFloat
    let index: Int
    let isWhite: Bool
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let midY = height * (0.3 + CGFloat(index) * 0.15)
        let amplitude: CGFloat = 30 + CGFloat(index) * 10
        let frequency: CGFloat = 0.008 + CGFloat(index) * 0.002
        
        path.move(to: CGPoint(x: 0, y: midY))
        
        for x in stride(from: 0, through: width, by: 2) {
            let y = midY + amplitude * sin(frequency * x + phase + CGFloat(index))
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        return path
    }
}

// MARK: - Glass Card
struct GlassCard<Content: View>: View {
    let content: Content
    let isWhite: Bool
    var radius: CGFloat = 28
    var blur: CGFloat = 10
    var padding: EdgeInsets = EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
    var onTap: (() -> Void)?
    
    init(isWhite: Bool, radius: CGFloat = 28, blur: CGFloat = 10, padding: EdgeInsets = EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18), onTap: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.isWhite = isWhite
        self.radius = radius
        self.blur = blur
        self.padding = padding
        self.onTap = onTap
        self.content = content()
    }
    
    var body: some View {
        let palette = GlassPalette(isWhite: isWhite)
        let sigma = blur * 0.42
        
        ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(
                    LinearGradient(
                        colors: [palette.cardTop, palette.cardBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            if sigma > 0.3 {
                RoundedRectangle(cornerRadius: radius)
                    .fill(.clear)
                    .background(.ultraThinMaterial)
                    .mask(RoundedRectangle(cornerRadius: radius))
            }
            
            content
                .padding(padding)
        }
        .overlay(
            GlassRim(radius: radius, isWhite: isWhite)
        )
        .shadow(color: (isWhite ? Color(hex: 0x0E3B1C) : .black).opacity(isWhite ? 0.20 : 0.60), radius: radius > 80 ? 16 : 9, y: radius > 80 ? 10 : 6)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .scaleEffect(isPressed ? 0.985 : 1.0)
        .animation(.easeOut(duration: 0.11), value: isPressed)
        .onTapGesture {
            guard onTap != nil else { return }
            withAnimation(.easeOut(duration: 0.11)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
                withAnimation(.easeOut(duration: 0.11)) {
                    isPressed = false
                }
                onTap?()
            }
        }
    }
    
    @State private var isPressed = false
}

// MARK: - Glass Rim Effect
private struct GlassRim: View {
    let radius: CGFloat
    let isWhite: Bool
    
    var body: some View {
        GeometryReader { geo in
            let rect = geo.frame(in: .local)
            let edgeW = min(geo.size.minDimension * 0.20, 14.0)
            let palette = GlassPalette(isWhite: isWhite)
            
            ZStack {
                // Rim stroke
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                (isWhite ? .white : Color(hex: 0xE4FFE8)).opacity(isWhite ? 1.0 : 0.85),
                                .white.opacity(0.08),
                                .clear,
                                palette.accent.opacity(isWhite ? 0.9 : 0.55)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.3
                    )
                
                // Thickness highlight
                RoundedRectangle(cornerRadius: radius)
                    .inset(by: edgeW / 2)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(isWhite ? 0.90 : 0.45),
                                .white.opacity(isWhite ? 0.12 : 0.04),
                                .white.opacity(isWhite ? 0.12 : 0.04),
                                palette.accent.opacity(isWhite ? 0.60 : 0.42)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: edgeW
                    )
                    .blur(radius: edgeW * 0.55)
                    .mask(
                        RoundedRectangle(cornerRadius: radius)
                            .strokeBorder(lineWidth: edgeW * 2)
                    )
                
                // Top gloss
                RoundedRectangle(cornerRadius: min(30, radius))
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(isWhite ? 0.60 : 0.22), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: min(geo.size.height * 0.34, 30))
                    .offset(y: -geo.size.height / 2 + min(geo.size.height * 0.34, 30) / 2 + 2.5)
                    .mask(RoundedRectangle(cornerRadius: radius).padding(-1))
                
                // Iridescent overlay
                RoundedRectangle(cornerRadius: radius)
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.accent.opacity(isWhite ? 0.14 : 0.16),
                                .clear,
                                Color(hex: 0xC8FFB0).opacity(isWhite ? 0 : 0.07),
                                palette.accent.opacity(isWhite ? 0.10 : 0.13)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
    }
}

// MARK: - Glass Button
struct GlassButton: View {
    let label: String
    var icon: Image?
    let isWhite: Bool
    var active: Bool = false
    var danger: Bool = false
    var expand: Bool = false
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        let palette = GlassPalette(isWhite: isWhite)
        let tintColor = danger ? palette.danger : (active ? palette.accent : nil)
        let textColor = danger ? palette.danger : (active ? palette.accent : palette.fg)
        
        Button(action: {
            HapticManager.impact(.light)
            action()
        }) {
            GlassCard(isWhite: isWhite, radius: 999, blur: 10, tint: tintColor, padding: EdgeInsets(top: 14, leading: 22, bottom: 14, trailing: 22)) {
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
        .buttonStyle(.plain)
        .disabled(action == nil)
        .opacity(action == nil ? 0.45 : 1.0)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.easeOut(duration: 0.11), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeOut(duration: 0.11)) { isPressed = pressing }
        }, perform: {})
    }
}

extension GlassCard {
    init(isWhite: Bool, radius: CGFloat = 28, blur: CGFloat = 10, tint: Color? = nil, padding: EdgeInsets = EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18), onTap: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.isWhite = isWhite
        self.radius = radius
        self.blur = blur
        self.padding = padding
        self.onTap = onTap
        self.content = content()
    }
}

// MARK: - Glass Icon Button
struct GlassIconButton: View {
    let icon: Image
    let isWhite: Bool
    var danger: Bool = false
    var size: CGFloat = 44
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        let palette = GlassPalette(isWhite: isWhite)
        let tint = danger ? palette.danger : nil
        
        Button(action: {
            HapticManager.impact(.light)
            action()
        }) {
            GlassCard(isWhite: isWhite, radius: 999, blur: 0, tint: tint, padding: .zero) {
                icon
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundStyle(danger ? palette.danger : palette.fg)
                    .frame(width: size, height: size)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(.easeOut(duration: 0.11), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeOut(duration: 0.11)) { isPressed = pressing }
        }, perform: {})
    }
}

// MARK: - Glass Chip
struct GlassChip: View {
    let label: String
    var icon: Image?
    let isWhite: Bool
    var selected: Bool = false
    var mono: Bool = false
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        let palette = GlassPalette(isWhite: isWhite)
        let color = selected ? palette.accent : palette.fg
        
        Button(action: {
            HapticManager.impact(.light)
            action()
        }) {
            GlassCard(isWhite: isWhite, radius: 999, blur: 0, tint: selected ? palette.accent : nil, padding: EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15)) {
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
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.easeOut(duration: 0.11), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeOut(duration: 0.11)) { isPressed = pressing }
        }, perform: {})
    }
}

// MARK: - Glass TextField
struct GlassTextField: View {
    @Binding var text: String
    let isWhite: Bool
    var placeholder: String = ""
    var label: String?
    var keyboardType: UIKeyboardType = .default
    var onSubmit: (() -> Void)?
    var suffix: (() -> AnyView)?
    
    var body: some View {
        let palette = GlassPalette(isWhite: isWhite)
        
        GlassCard(isWhite: isWhite, radius: 999, blur: 8, padding: EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: suffix == nil ? 20 : 6)) {
            TextField(placeholder, text: $text, onCommit: { onSubmit?() })
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 16, design: .default))
                .foregroundStyle(palette.fg)
                .accentColor(palette.accent)
                .submitLabel(.done)
        }
    }
}

// MARK: - Glass Label
struct GlassLabel: View {
    let text: String
    let isWhite: Bool
    
    var body: some View {
        let palette = GlassPalette(isWhite: isWhite)
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(palette.subtle)
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
                RoundedRectangle(cornerRadius: height)
                    .fill(palette.fg.opacity(0.10))
                
                RoundedRectangle(cornerRadius: height)
                    .fill(
                        LinearGradient(colors: [c.opacity(0.55), c], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: geo.size.width * v)
                    .shadow(color: c.opacity(0.55), radius: 12)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.18), value: value)
    }
}

// MARK: - Haptic Manager
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

// MARK: - Color Extension
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

// MARK: - Comparable Clamping
extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - ByteCountFormatter Extension
extension ByteCountFormatter {
    static func string(fromByteCount bytes: Int64, countStyle: ByteCountFormatter.CountStyle = .file) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = countStyle
        return formatter.string(fromByteCount: bytes)
    }
}

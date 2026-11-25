import SwiftUI
import UIKit

// MARK: - Brand

extension Color {
    /// System-style green (matches iOS "Messages/FaceTime" green).
    static let fdAccent = Color(red: 0.19, green: 0.82, blue: 0.35)
}

// MARK: - Background

/// Soft, static backdrop so the Liquid Glass has something to refract.
struct FDBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)

            RadialGradient(
                colors: [Color.fdAccent.opacity(scheme == .dark ? 0.30 : 0.24), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 460
            )
            RadialGradient(
                colors: [Color.teal.opacity(scheme == .dark ? 0.24 : 0.18), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 520
            )
            RadialGradient(
                colors: [Color.blue.opacity(scheme == .dark ? 0.16 : 0.10), .clear],
                center: .trailing,
                startRadius: 0,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Liquid Glass (iOS 26 / 27) with graceful fallback

#if compiler(>=6.2)
@available(iOS 26.0, *)
private func makeGlass(tint: Color?, interactive: Bool) -> Glass {
    var glass = Glass.regular
    if let tint = tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return glass
}
#endif

extension View {
    /// Applies Liquid Glass on iOS 26+/27, and a material look on older systems.
    @ViewBuilder
    func fdGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(makeGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            self.fdMaterial(in: shape, tint: tint)
        }
        #else
        self.fdMaterial(in: shape, tint: tint)
        #endif
    }

    fileprivate func fdMaterial<S: Shape>(in shape: S, tint: Color?) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .background((tint ?? .clear).opacity(0.18), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6))
            .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
    }

    /// A rounded glass card with built-in padding.
    func fdCard(radius: CGFloat = 26, tint: Color? = nil, padding: CGFloat = 16, interactive: Bool = false) -> some View {
        self
            .padding(padding)
            .fdGlass(in: RoundedRectangle(cornerRadius: radius, style: .continuous), tint: tint, interactive: interactive)
    }

    /// `.glass` / `.glassProminent` button styles on iOS 26+, bordered styles before that.
    @ViewBuilder
    func fdButtonStyle(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
        #else
        if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
        #endif
    }
}

/// Groups nearby glass elements so they blend and morph like system controls.
struct FDGlassContainer<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

// MARK: - Small building blocks

struct FDSectionHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            trailing
        }
        .padding(.horizontal, 8)
    }
}

extension FDSectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

/// Round glass icon button (used in the transfer screen).
struct FDIconButton: View {
    let systemName: String
    var tint: Color? = nil
    var size: CGFloat = 46
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.impact(.light)
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(tint ?? .primary)
                .frame(width: size, height: size)
                .fdGlass(in: Circle(), tint: tint?.opacity(0.35), interactive: true)
        }
        .buttonStyle(.plain)
    }
}

struct FDProgressRing: View {
    let value: Double
    var color: Color = .fdAccent
    var lineWidth: CGFloat = 18

    var body: some View {
        let clamped = value.clamped(to: 0...1)

        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(clamped, 0.002))
                .stroke(
                    AngularGradient(colors: [color.opacity(0.65), color], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(clamped, 0.002))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.45), radius: 10)
                .animation(.easeOut(duration: 0.2), value: clamped)
        }
    }
}

func fileIconName(for fileName: String) -> String {
    switch (fileName as NSString).pathExtension.lowercased() {
    case "jpg", "jpeg", "png", "heic", "gif", "webp": return "photo.fill"
    case "mp4", "mov", "mkv", "avi": return "video.fill"
    case "mp3", "wav", "m4a", "flac": return "music.note"
    case "zip", "rar", "7z", "tar", "gz": return "archivebox.fill"
    case "pdf": return "doc.richtext.fill"
    default: return "doc.fill"
    }
}

// MARK: - Helpers

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

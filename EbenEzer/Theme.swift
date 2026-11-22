//
//  Theme.swift
//  Eben-Ezer
//
//  Farben, Schriften und gemeinsame Bausteine im GEC-Design (gec-hn.de).
//

import SwiftUI
import UIKit
import CoreText

// MARK: - Farben

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    static let green800 = Color(hex: 0x1D4855)
    static let green600 = Color(hex: 0x177365)
    static let green400 = Color(hex: 0xA3D0A4)
    static let blue400 = Color(hex: 0xCCE7E4)
    static let gold100 = Color(hex: 0xFEF4E0)
    static let gold400 = Color(hex: 0xEABF46)
    static let gold800 = Color(hex: 0xCBAB3B)
    static let offBlack = Color(hex: 0x1F2837)
    static let offWhite = Color(hex: 0xFFFEFC)
    static let gray300 = Color(hex: 0xC1C1C1)
    static let gray500 = Color(hex: 0x828282)
    static let gray700 = Color(hex: 0x5D5D5D)
    static let red800 = Color(hex: 0xE84D14)
    static let outlineSoft = Color(hex: 0xEFE6D2)
}

// MARK: - Schriften

/// Schriftgrößen wie in der Android-App.
enum TS {
    static let display = Font.system(size: 34, weight: .heavy)
    static let headlineM = Font.system(size: 28, weight: .heavy)
    static let headlineS = Font.system(size: 24, weight: .heavy)
    static let titleL = Font.system(size: 21, weight: .bold)
    static let titleM = Font.system(size: 17, weight: .bold)
    static let bodyL = Font.system(size: 17, weight: .medium)
    static let bodyM = Font.system(size: 15, weight: .medium)
    static let labelL = Font.system(size: 16, weight: .bold)
    static let labelM = Font.system(size: 13, weight: .semibold)
    static let labelS = Font.system(size: 12, weight: .semibold)
}

/// Playfair Display Bold Italic – wie im Design „Jahr des Gebets“.
enum Fonts {
    private static let descriptor: CTFontDescriptor? = {
        guard let url = Bundle.main.url(forResource: "PlayfairDisplay-Italic", withExtension: "ttf"),
              let list = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let base = list.first else { return nil }
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        // Variable Schrift: Strichstärke 700 (fett)
        let wght = 0x7767_6874 // 'wght'
        let attributes = [kCTFontVariationAttribute as String: [wght: 700]] as CFDictionary
        return CTFontDescriptorCreateCopyWithAttributes(base, attributes)
    }()

    static func serifUIFont(_ size: CGFloat) -> UIFont {
        if let d = descriptor {
            return CTFontCreateWithFontDescriptor(d, size, nil) as UIFont
        }
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        if let serif = base.fontDescriptor.withDesign(.serif)?.withSymbolicTraits([.traitItalic, .traitBold]) {
            return UIFont(descriptor: serif, size: size)
        }
        return base
    }

    static func serif(_ size: CGFloat) -> Font { Font(serifUIFont(size)) }
}

// MARK: - Logo & Untertitel

/// Aufgeschichtete Gedenksteine (1. Samuel 7,12).
struct StonesLogo: View {
    var size: CGFloat = 36

    var body: some View {
        let s = size / 48
        ZStack(alignment: .topLeading) {
            stone(cx: 24, cy: 36, rx: 20, ry: 9, color: .gold400, s: s)
            stone(cx: 22, cy: 22, rx: 15, ry: 7.5, color: .gold800, s: s)
            stone(cx: 25, cy: 9.5, rx: 10, ry: 6, color: .gold400, s: s)
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func stone(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, color: Color, s: CGFloat) -> some View {
        Ellipse()
            .fill(color)
            .frame(width: 2 * rx * s, height: 2 * ry * s)
            .offset(x: (cx - rx) * s, y: (cy - ry) * s)
    }
}

/// Untertitel „Zeichen seiner Hilfe“.
struct Tagline: View {
    var size: CGFloat = 18
    var serifColor: Color = .green800
    var sansColor: Color = .gold800

    var body: some View {
        (Text("Zeichen ").font(Fonts.serif(size)).foregroundColor(serifColor)
            + Text("seiner").font(.system(size: size * 0.78, weight: .heavy)).foregroundColor(sansColor).kerning(-0.03 * size * 0.78)
            + Text(" Hilfe").font(Fonts.serif(size)).foregroundColor(serifColor))
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - Bausteine

struct Overline: View {
    let text: String
    var color: Color = .gold800

    var body: some View {
        Text(text.uppercased(with: Locale(identifier: "de_DE")))
            .font(TS.labelM)
            .kerning(0.8)
            .foregroundColor(color)
    }
}

struct CategoryPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(TS.labelS)
            .foregroundColor(.green800)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.gold100))
    }
}

/// Auswählbarer Filter-Chip.
struct Chip: View {
    let label: String
    var selected: Bool
    var icon: String? = nil
    var iconColor: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(iconColor ?? (selected ? .gold400 : .green800))
                }
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(selected ? .offWhite : .offBlack)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(selected ? Color.green800 : Color.white))
            .overlay(Capsule().stroke(selected ? Color.clear : Color.gray300, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Gefüllter Knopf (Standard: Gold).
struct PillButtonStyle: ButtonStyle {
    var fill: Color = .gold400
    var text: Color = .offBlack
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, fill: fill, text: text, fullWidth: fullWidth, outlined: false)
    }
}

/// Umrandeter Knopf.
struct OutlinePillStyle: ButtonStyle {
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, fill: .clear, text: .green800, fullWidth: fullWidth, outlined: true)
    }
}

private struct PillBody: View {
    let configuration: ButtonStyleConfiguration
    let fill: Color
    let text: Color
    let fullWidth: Bool
    let outlined: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(TS.labelL)
            .foregroundColor(text)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(RoundedRectangle(cornerRadius: 23).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 23).stroke(outlined ? Color.gray300 : Color.clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 23))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}

/// Überschrift in Goldbuchstaben + Inhalt.
struct LabeledSection<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Overline(text: label)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Zeilenumbrechende Anordnung (wie FlowRow in Android).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += s.width + spacing
            lineHeight = max(lineHeight, s.height)
            widest = max(widest, x - spacing)
        }
        let width = (proposal.width.map { $0.isFinite ? $0 : widest }) ?? widest
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineHeight = max(lineHeight, s.height)
        }
    }
}

/// Zeigt eine Meldung als Alert an, solange `message` gesetzt ist.
extension View {
    func messageAlert(_ message: Binding<String?>) -> some View {
        alert(message.wrappedValue ?? "",
              isPresented: Binding(get: { message.wrappedValue != nil },
                                   set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }
}

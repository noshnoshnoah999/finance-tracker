// Theme.swift — Budget (iOS/Mac)
// The LATTE palette from app.html, ported to SwiftUI Colors.

import SwiftUI

extension Color {
    init(hex: String, opacity: Double = 1) {
        var h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

/// Coffee — warm tan/latte gradient bg, soft cream cards, espresso text, caramel accent
/// (olive green = positive, terracotta rose = negative). Matches StudyTrack + Nudge.
enum T {
    static let bgTop    = Color(hex: "c2ab8b")
    static let bgMid    = Color(hex: "b59e7d")
    static let bgBottom = Color(hex: "a68d6b")

    static let card    = Color(hex: "f1eada")
    static let cardAlt = Color(hex: "cec1a8")
    static let border  = Color(hex: "d6c9b0")

    static let text  = Color(hex: "584738")
    static let sub   = Color(hex: "6f5d49")
    static let muted = Color(hex: "9a917f")

    static let greenD  = Color(hex: "6f7a48")
    static let green   = Color(hex: "8a9560")
    static let greenBg = Color(hex: "6f7a48", opacity: 0.16)

    static let blueD  = Color(hex: "7a6854")
    static let blue   = Color(hex: "9a8a74")
    static let blueBg = Color(hex: "7a6854", opacity: 0.13)

    static let lavD  = Color(hex: "8a7c64")
    static let lavBg = Color(hex: "8a7c64", opacity: 0.16)

    static let peachD  = Color(hex: "b08a55")
    static let peach   = Color(hex: "c5a878")
    static let peachBg = Color(hex: "b08a55", opacity: 0.16)

    static let roseD  = Color(hex: "9c5240")
    static let rose   = Color(hex: "ba7762")
    static let roseBg = Color(hex: "9c5240", opacity: 0.15)

    static let white  = Color.white
    static let accent = Color(hex: "584738")

    static var background: LinearGradient {
        LinearGradient(colors: [bgTop, bgMid, bgBottom], startPoint: .top, endPoint: .bottom)
    }
}

/// A frosted card surface matching the web `crd` style.
struct Card: ViewModifier {
    var padding: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T.card)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(T.border, lineWidth: 1))
    }
}
extension View {
    func card(padding: CGFloat = 20) -> some View { modifier(Card(padding: padding)) }
}

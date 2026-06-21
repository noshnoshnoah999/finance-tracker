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

/// Clean Light + Indigo — crisp white/soft-grey, calm indigo accent (emerald = positive, red = negative).
enum T {
    static let bgTop    = Color(hex: "f8f9fb")
    static let bgMid    = Color(hex: "f6f7f9")
    static let bgBottom = Color(hex: "eef0f5")

    static let card    = Color(hex: "ffffff")
    static let cardAlt = Color(hex: "eef0f5")
    static let border  = Color(hex: "e4e7ef")

    static let text  = Color(hex: "16181f")
    static let sub   = Color(hex: "6b7180")
    static let muted = Color(hex: "9aa0b0")

    static let greenD  = Color(hex: "10b981")
    static let green   = Color(hex: "34d399")
    static let greenBg = Color(hex: "10b981", opacity: 0.12)

    static let blueD  = Color(hex: "6366f1")
    static let blue   = Color(hex: "818cf8")
    static let blueBg = Color(hex: "6366f1", opacity: 0.12)

    static let lavD  = Color(hex: "8b5cf6")
    static let lavBg = Color(hex: "8b5cf6", opacity: 0.12)

    static let peachD  = Color(hex: "f59e0b")
    static let peach   = Color(hex: "fbbf24")
    static let peachBg = Color(hex: "f59e0b", opacity: 0.12)

    static let roseD  = Color(hex: "ef4444")
    static let rose   = Color(hex: "f87171")
    static let roseBg = Color(hex: "ef4444", opacity: 0.12)

    static let white  = Color.white
    static let accent = Color(hex: "6366f1")

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

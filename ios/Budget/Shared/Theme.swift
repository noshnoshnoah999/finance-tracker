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

/// The Latte theme (the app's default warm-brown look). Other web themes exist but
/// Latte is the migrated default, so the native app ships it.
enum T {
    static let bgTop    = Color(hex: "c4a778")
    static let bgMid    = Color(hex: "b38f57")
    static let bgBottom = Color(hex: "9e7842")

    static let card    = Color(hex: "f3e7d2", opacity: 0.52)
    static let cardAlt = Color(hex: "e4d2b4", opacity: 0.60)
    static let border  = Color(hex: "fff8e8", opacity: 0.38)

    static let text  = Color(hex: "2a1c0e")
    static let sub   = Color(hex: "7d5f3a")
    static let muted = Color(hex: "9c7e54")

    static let greenD  = Color(hex: "5a7330")
    static let green   = Color(hex: "7a9442")
    static let greenBg = Color(hex: "6e8c37", opacity: 0.22)

    static let blueD  = Color(hex: "4f5fd0")
    static let blue   = Color(hex: "7d8ae8")
    static let blueBg = Color(hex: "5b6ee0", opacity: 0.18)

    static let lavD  = Color(hex: "6f5fd6")
    static let lavBg = Color(hex: "6f5fd6", opacity: 0.18)

    static let peachD  = Color(hex: "a85d28")
    static let peach   = Color(hex: "c98748")
    static let peachBg = Color(hex: "a85d28", opacity: 0.18)

    static let roseD  = Color(hex: "bb4a68")
    static let rose   = Color(hex: "d9779a")
    static let roseBg = Color(hex: "bb4a68", opacity: 0.18)

    static let white  = Color.white
    static let accent = Color(hex: "643f1f")

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

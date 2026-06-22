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

/// Ocean — rich blue→indigo→violet gradient bg, soft tinted cards, indigo accent (teal = positive, red = negative).
enum T {
    static let bgTop    = Color(hex: "7c9ff0")
    static let bgMid    = Color(hex: "8d8eef")
    static let bgBottom = Color(hex: "a98bef")

    static let card    = Color(hex: "f1f4fd")
    static let cardAlt = Color(hex: "e3e9fb")
    static let border  = Color(hex: "d2dbf4")

    static let text  = Color(hex: "1a2342")
    static let sub   = Color(hex: "5a679a")
    static let muted = Color(hex: "8e98c0")

    static let greenD  = Color(hex: "0d9488")
    static let green   = Color(hex: "14b8a6")
    static let greenBg = Color(hex: "0d9488", opacity: 0.13)

    static let blueD  = Color(hex: "2563eb")
    static let blue   = Color(hex: "60a5fa")
    static let blueBg = Color(hex: "2563eb", opacity: 0.13)

    static let lavD  = Color(hex: "6d5dea")
    static let lavBg = Color(hex: "6d5dea", opacity: 0.14)

    static let peachD  = Color(hex: "ef8f1c")
    static let peach   = Color(hex: "f9b53d")
    static let peachBg = Color(hex: "ef8f1c", opacity: 0.14)

    static let roseD  = Color(hex: "e11d48")
    static let rose   = Color(hex: "fb7185")
    static let roseBg = Color(hex: "e11d48", opacity: 0.12)

    static let white  = Color.white
    static let accent = Color(hex: "5b6ee8")

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

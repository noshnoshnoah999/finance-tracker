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

/// The StudyTrack "Coffee" theme — warm dark browns + one bold orange accent
/// (green = positive, red = negative). The native default.
enum T {
    static let bgTop    = Color(hex: "1c1209")
    static let bgMid    = Color(hex: "160e06")
    static let bgBottom = Color(hex: "100a03")

    static let card    = Color(hex: "211508")
    static let cardAlt = Color(hex: "2c1e0e")
    static let border  = Color(hex: "f97316", opacity: 0.14)

    static let text  = Color(hex: "f5ede4")
    static let sub   = Color(hex: "c0916a")
    static let muted = Color(hex: "8a5c38")

    static let greenD  = Color(hex: "00c896")
    static let green   = Color(hex: "2fd3a8")
    static let greenBg = Color(hex: "00c896", opacity: 0.16)

    static let blueD  = Color(hex: "f97316")
    static let blue   = Color(hex: "fb923c")
    static let blueBg = Color(hex: "f97316", opacity: 0.18)

    static let lavD  = Color(hex: "f97316")
    static let lavBg = Color(hex: "f97316", opacity: 0.18)

    static let peachD  = Color(hex: "e86a10")
    static let peach   = Color(hex: "fb923c")
    static let peachBg = Color(hex: "f97316", opacity: 0.18)

    static let roseD  = Color(hex: "ff4d6a")
    static let rose   = Color(hex: "ff6b82")
    static let roseBg = Color(hex: "ff4d6a", opacity: 0.16)

    static let white  = Color.white
    static let accent = Color(hex: "f97316")

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

import SwiftUI
import UIKit
import BitcoinKit

/// The logo palette: Bitcoin orange plus the three block shades, on a warm near-black (or warm off-white in light mode).
enum Theme {
    static let orange = Color(hex: 0xF7931A)
    static let orangeMid = Color(hex: 0xD88218)
    static let orangeDeep = Color(hex: 0xB9701A)
    static let up = Color(hex: 0x34C759)
    static let down = Color(hex: 0xFF453A)

    static let background = Color(light: 0xF6F3EE, dark: 0x09090B)
    static let card = Color(light: 0xFFFFFF, dark: 0x16130F)
    static let cardRaised = Color(light: 0xF1ECE4, dark: 0x221D17)
    static let border = Color(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.08)

    /// The three block shades, used as chart series colours.
    static let series: [Color] = [orange, orangeMid, orangeDeep]

    /// Donut slices: the logo shades first, then warm greys.
    static let slices: [Color] = [
        orange, orangeMid, orangeDeep,
        Color(hex: 0xF5B461), Color(hex: 0x8C5A1E), Color(hex: 0xA1A1AA),
        Color(hex: 0x71717A), Color(hex: 0x52525B), Color(hex: 0x3F3F46),
    ]

    static func change(_ percent: Double?) -> Color {
        guard let percent else { return .secondary }
        return percent >= 0 ? up : down
    }

    /// Fee level text: green when cheap, through the oranges, red when very busy.
    static func congestion(_ c: Congestion) -> Color {
        switch c {
        case .low: up
        case .medium: orange
        case .high: orangeMid
        case .veryHigh: down
        }
    }

    /// Projected-block colour: brighter orange for higher fee rates.
    static func feeIntensity(_ rate: Double) -> Double {
        let clamped = min(max(rate, 0.1), 50)
        return 0.35 + 0.65 * (log(clamped / 0.1) / log(500))
    }
}

extension Font {
    /// Rounded, fixed-width digits so values don't shift as they change.
    static func number(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight).monospacedDigit()
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            let alpha = traits.userInterfaceStyle == .dark ? darkAlpha : lightAlpha
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: alpha)
        })
    }
}

extension Appearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

/// Dark-grey card with a fine border.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.border))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

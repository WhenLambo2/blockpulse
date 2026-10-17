import Foundation

/// All user-facing number formatting. Fixed en_US grouping so widgets and tests are deterministic.
public enum Format {
    public static func grouped(_ value: Double, fractionDigits: Int = 0) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.minimumFractionDigits = fractionDigits
        f.maximumFractionDigits = fractionDigits
        f.roundingMode = .halfUp
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// "€73,984"
    public static func price(_ value: Double, _ currency: Currency) -> String {
        currency.symbol + grouped(value)
    }

    /// "€74k", "€9.5k", "€950", "$1.2M"
    public static func compactPrice(_ value: Double, _ currency: Currency) -> String {
        currency.symbol + compact(value)
    }

    /// "77.1k", "950", "1.2M"
    public static func compactCount(_ value: Int) -> String {
        compact(Double(value), alwaysOneDecimal: true)
    }

    /// Percent units in, "+4.72%" / "-0.89%" out. Values that round to zero render "+0.00%".
    public static func signedPercent(_ percent: Double) -> String {
        let rounded = (percent * 100).rounded() / 100
        let sign = rounded < 0 ? "-" : "+"
        return sign + String(format: "%.2f", abs(rounded)) + "%"
    }

    /// Change over a chart period: "+4.72%" up to +1000%, then a multiple ("×12", "×1,371")
    /// so all-time moves stay short enough for one line.
    public static func change(_ percent: Double) -> String {
        guard percent >= 1000 else { return signedPercent(percent) }
        let multiple = 1 + percent / 100
        return "×" + (multiple < 100 ? trimmed(String(format: "%.1f", multiple)) : grouped(multiple))
    }

    public static func sats(_ value: Int) -> String { grouped(Double(value)) + " sats" }

    /// < 1: two decimals trimmed ("0.35", "0.1"); 1–10: one decimal trimmed ("2.2", "1"); ≥ 10: integer,
    /// grouped from 1,000 up ("3,604,819").
    public static func feeRateNumber(_ value: Double) -> String {
        if value <= 0 { return "0" }
        if value < 1 { return trimmed(String(format: "%.2f", value)) }
        if value < 10 { return trimmed(String(format: "%.1f", value)) }
        if value < 1000 { return String(Int(value.rounded())) }
        return grouped(value.rounded())
    }

    public static func feeRate(_ value: Double) -> String { feeRateNumber(value) + " sat/vB" }

    /// "#971,150"
    public static func blockHeight(_ height: Int) -> String { "#" + grouped(Double(height)) }

    /// "38.5 vMB"
    public static func vMB(_ vsize: Int) -> String { String(format: "%.1f", Double(vsize) / 1_000_000) + " vMB" }

    /// Lock Screen inline: "₿ €73,984 · 2 sat/vB". The line shares its row with the date, so it holds
    /// two values at most: the block height only stands in when there is no price.
    public static func inline(_ snapshot: BitcoinSnapshot, _ currency: Currency) -> String {
        var parts: [String] = []
        if let p = snapshot.price { parts.append(price(p.price(in: currency), currency)) }
        else if let h = snapshot.tipHeight { parts.append(blockHeight(h)) }
        if let f = snapshot.fees { parts.append(feeRate(f.fastestFee)) }
        return parts.isEmpty ? "₿ —" : "₿ " + parts.joined(separator: " · ")
    }

    // MARK: - Helpers

    private static func compact(_ value: Double, alwaysOneDecimal: Bool = false) -> String {
        let v = abs(value)
        let sign = value < 0 ? "-" : ""
        if v >= 1_000_000 { return sign + trimmed(String(format: "%.1f", v / 1_000_000)) + "M" }
        if v >= 10_000 && !alwaysOneDecimal { return sign + String(Int((v / 1_000).rounded())) + "k" }
        if v >= 1_000 { return sign + trimmed(String(format: "%.1f", v / 1_000)) + "k" }
        return sign + String(Int(v.rounded()))
    }

    /// "2.0" -> "2", "0.30" -> "0.3", "0.35" -> "0.35"
    private static func trimmed(_ s: String) -> String {
        guard s.contains(".") else { return s }
        var out = s
        while out.hasSuffix("0") { out.removeLast() }
        if out.hasSuffix(".") { out.removeLast() }
        return out
    }
}

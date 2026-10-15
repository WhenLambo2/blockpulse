import AppIntents
import BitcoinKit

enum CurrencyOption: String, AppEnum {
    case appDefault, eur, usd

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Currency"
    static let caseDisplayRepresentations: [CurrencyOption: DisplayRepresentation] = [
        .appDefault: "App setting",
        .eur: "EUR (€)",
        .usd: "USD ($)",
    ]

    func resolve(default fallback: Currency) -> Currency {
        switch self {
        case .appDefault: fallback
        case .eur: .eur
        case .usd: .usd
        }
    }
}

enum LockMetric: String, AppEnum {
    case price, fee, height

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Metric"
    static let caseDisplayRepresentations: [LockMetric: DisplayRepresentation] = [
        .price: "Price",
        .fee: "Fastest fee",
        .height: "Block height",
    ]
}

/// Implemented by every widget configuration so one provider serves all widgets.
protocol SnapshotWidgetIntent: WidgetConfigurationIntent {
    var currencyOption: CurrencyOption { get }
    var lockMetric: LockMetric { get }
}

struct CurrencyIntent: SnapshotWidgetIntent {
    static let title: LocalizedStringResource = "Currency"
    static let description = IntentDescription("Choose the currency shown in this widget.")

    @Parameter(title: "Currency", default: .appDefault)
    var currency: CurrencyOption

    init() {}

    var currencyOption: CurrencyOption { currency }
    var lockMetric: LockMetric { .price }
}

struct LockScreenIntent: SnapshotWidgetIntent {
    static let title: LocalizedStringResource = "Lock Screen"
    static let description = IntentDescription("Choose what the circular widget shows and the currency.")

    @Parameter(title: "Metric", default: .price)
    var metric: LockMetric

    @Parameter(title: "Currency", default: .appDefault)
    var currency: CurrencyOption

    init() {}

    var currencyOption: CurrencyOption { currency }
    var lockMetric: LockMetric { metric }
}

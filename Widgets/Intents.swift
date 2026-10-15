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

/// What a circular Lock Screen widget shows. Each value is its own widget in the gallery,
/// so two circular widgets side by side never show the same number by default.
enum LockMetric: String {
    case price, fee, height
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

/// The fee and block height widgets have nothing to configure.
struct LockFeeIntent: SnapshotWidgetIntent {
    static let title: LocalizedStringResource = "Fastest fee"
    init() {}
    var currencyOption: CurrencyOption { .appDefault }
    var lockMetric: LockMetric { .fee }
}

struct LockHeightIntent: SnapshotWidgetIntent {
    static let title: LocalizedStringResource = "Block height"
    init() {}
    var currencyOption: CurrencyOption { .appDefault }
    var lockMetric: LockMetric { .height }
}

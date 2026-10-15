import Foundation
import Testing
@testable import BitcoinKit

@Suite struct AppSettingsTests {
    let defaults: UserDefaults
    let settings: AppSettings

    init() {
        let suite = "blockpulse-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        settings = AppSettings(defaults: defaults)
    }

    @Test func defaultCurrencyIsEUR() { #expect(settings.currency == .eur) }

    @Test func currencyPersists() {
        settings.currency = .usd
        #expect(AppSettings(defaults: defaults).currency == .usd)
        #expect(defaults.string(forKey: AppSettings.Keys.currency) == "USD")
    }

    @Test func unknownStoredCurrencyFallsBack() {
        defaults.set("GBP", forKey: AppSettings.Keys.currency)
        #expect(settings.currency == .eur)
    }

    @Test func defaultBaseURL() {
        #expect(settings.baseURL == MempoolClient.defaultBaseURL)
        #expect(!settings.usesCustomInstance)
    }

    @Test func migrationClearsStoredBlockriseOnce() {
        settings.baseURLString = "https://blockrise.mempool.space"
        settings.migrateToPublicDefault()
        #expect(settings.baseURL == MempoolClient.defaultBaseURL)
        // Choosing Blockrise again afterwards sticks.
        settings.baseURLString = "https://blockrise.mempool.space"
        settings.migrateToPublicDefault()
        #expect(settings.baseURL == MempoolClient.blockriseBaseURL)
        #expect(settings.usesCustomInstance)
    }

    @Test func migrationKeepsOtherCustomInstances() {
        settings.baseURLString = "http://umbrel.local:3006"
        settings.migrateToPublicDefault()
        #expect(settings.baseURL.absoluteString == "http://umbrel.local:3006")
    }

    @Test(arguments: [
        ("https://blockrise.mempool.space", "https://blockrise.mempool.space"),
        ("  https://mempool.space/  ", "https://mempool.space"),
        ("https://mempool.space///", "https://mempool.space"),
        ("http://umbrel.local:3006", "http://umbrel.local:3006"),
    ])
    func validURLs(input: String, expected: String) {
        #expect(AppSettings.validatedBaseURL(input)?.absoluteString == expected)
    }

    @Test(arguments: ["", "   ", "mempool.space", "ftp://mempool.space", "not a url", "https://", "https://mempool.space/?a=b", "https://mempool.space#x"])
    func invalidURLs(input: String) {
        #expect(AppSettings.validatedBaseURL(input) == nil)
    }

    @Test func nilURLIsInvalid() { #expect(AppSettings.validatedBaseURL(nil) == nil) }

    @Test func settingValidBaseURLStoresNormalised() {
        settings.baseURLString = " https://mempool.space/ "
        #expect(settings.baseURL.absoluteString == "https://mempool.space")
        #expect(defaults.string(forKey: AppSettings.Keys.baseURL) == "https://mempool.space")
    }

    @Test func settingInvalidBaseURLResetsToDefault() {
        settings.baseURLString = "https://mempool.space"
        settings.baseURLString = "garbage"
        #expect(settings.baseURL == MempoolClient.defaultBaseURL)
        #expect(defaults.string(forKey: AppSettings.Keys.baseURL) == nil)
    }

    @Test func corruptStoredURLFallsBack() {
        defaults.set("::::", forKey: AppSettings.Keys.baseURL)
        #expect(settings.baseURL == MempoolClient.defaultBaseURL)
    }

    @Test func makeClientUsesBaseURL() {
        settings.baseURLString = "https://mempool.space"
        #expect(settings.makeClient().baseURL.absoluteString == "https://mempool.space")
    }
}

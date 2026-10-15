import Foundation
import Testing
@testable import BitcoinKit

@Suite struct FormatTests {
    @Test func prices() {
        #expect(Format.price(73_984, .eur) == "€73,984")
        #expect(Format.price(82_565.4, .usd) == "$82,565")
        #expect(Format.price(999.6, .eur) == "€1,000")
    }

    @Test func compactPrices() {
        #expect(Format.compactPrice(73_984, .eur) == "€74k")
        #expect(Format.compactPrice(100_400, .usd) == "$100k")
        #expect(Format.compactPrice(9_540, .eur) == "€9.5k")
        #expect(Format.compactPrice(1_000, .eur) == "€1k")
        #expect(Format.compactPrice(950, .eur) == "€950")
        #expect(Format.compactPrice(1_234_567, .usd) == "$1.2M")
    }

    @Test func compactCounts() {
        #expect(Format.compactCount(950) == "950")
        #expect(Format.compactCount(77_148) == "77.1k")
        #expect(Format.compactCount(5_000) == "5k")
        #expect(Format.compactCount(971_160) == "971.2k")
        #expect(Format.compactCount(1_234_567) == "1.2M")
    }

    @Test func changeSwitchesToMultipleForHugeMoves() {
        #expect(Format.change(4.724) == "+4.72%")
        #expect(Format.change(-12.5) == "-12.50%")
        #expect(Format.change(999) == "+999.00%")
        #expect(Format.change(1_000) == "×11")
        #expect(Format.change(1_150) == "×12.5")
        #expect(Format.change(137_000) == "×1,371")
    }

    @Test func signedPercents() {
        #expect(Format.signedPercent(4.724) == "+4.72%")
        #expect(Format.signedPercent(-0.8935) == "-0.89%")
        #expect(Format.signedPercent(0) == "+0.00%")
        #expect(Format.signedPercent(-0.001) == "+0.00%")
    }

    @Test func satsAndHeights() {
        #expect(Format.sats(1_352) == "1,352 sats")
        #expect(Format.sats(1) == "1 sats")
        #expect(Format.blockHeight(971_150) == "#971,150")
        #expect(Format.vMB(38_536_434) == "38.5 vMB")
        #expect(Format.vMB(0) == "0.0 vMB")
    }

    @Test func feeRates() {
        #expect(Format.feeRate(2) == "2 sat/vB")
        #expect(Format.feeRate(0.3465) == "0.35 sat/vB")
        #expect(Format.feeRate(0.1) == "0.1 sat/vB")
        #expect(Format.feeRate(2.24) == "2.2 sat/vB")
        #expect(Format.feeRate(1.0) == "1 sat/vB")
        #expect(Format.feeRate(12.6) == "13 sat/vB")
        #expect(Format.feeRate(0) == "0 sat/vB")
        #expect(Format.feeRateNumber(0.3465) == "0.35")
    }

    @Test func inlineSummary() {
        let full = BitcoinSnapshot.sample()
        #expect(Format.inline(full, .eur) == "₿ €73,984 · #971,150 · 2 sat/vB")
        #expect(Format.inline(full, .usd) == "₿ $82,565 · #971,150 · 2 sat/vB")
        var noPrice = full
        noPrice.price = nil
        #expect(Format.inline(noPrice, .eur) == "₿ #971,150 · 2 sat/vB")
        let empty = BitcoinSnapshot(fetchedAt: .now, price: nil, blocks: [], fees: nil, mempool: nil, difficulty: nil)
        #expect(Format.inline(empty, .eur) == "₿ —")
    }
}

import Foundation
import Testing
@testable import BitcoinKit

@Suite struct SearchParserTests {
    static let genesisHash = "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"
    static let genesisTx = "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b"
    static let p2wpkh = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"
    static let p2wsh = "bc1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qccfmv3"
    static let taproot = "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0"
    static let now = Date(timeIntervalSince1970: 1_791_000_000)  // 2026-10-03

    func target(_ s: String, tip: Int? = 970_000) -> SearchTarget? {
        SearchParser.interpret(s, tip: tip, now: Self.now, timeZone: TimeZone(identifier: "UTC")!).target
    }

    func issue(_ s: String, tip: Int? = 970_000) -> SearchIssue? {
        SearchParser.interpret(s, tip: tip, now: Self.now, timeZone: TimeZone(identifier: "UTC")!).issue
    }

    @Test func addresses() {
        #expect(target("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa") == .address("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"))
        #expect(target("3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy") == .address("3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy"))
        #expect(target(Self.p2wpkh) == .address(Self.p2wpkh))
        #expect(target(Self.p2wsh) == .address(Self.p2wsh))
        #expect(target(Self.taproot) == .address(Self.taproot))
    }

    @Test func upperCaseQRAddressIsLowercased() {
        #expect(target(Self.p2wpkh.uppercased()) == .address(Self.p2wpkh))
    }

    @Test func checksumTyposAreCaught() {
        #expect(issue("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5") == .addressTypo)
        // Version 0 with a bech32m checksum (BIP350 invalid vector).
        #expect(issue("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kemeawh") == .addressTypo)
    }

    @Test func blockHashBeforeTransaction() {
        #expect(target(Self.genesisHash) == .blockHash(Self.genesisHash))
        #expect(target(Self.genesisHash.uppercased()) == .blockHash(Self.genesisHash))
    }

    @Test func transactions() {
        #expect(target(Self.genesisTx) == .transaction(txid: Self.genesisTx, output: nil))
        #expect(target(Self.genesisTx + ":1") == .transaction(txid: Self.genesisTx, output: 1))
        #expect(target(Self.genesisTx + ":01") == nil)
    }

    @Test func heights() {
        #expect(target("0") == .blockHeight(0))
        #expect(target("840000") == .blockHeight(840_000))
        #expect(target("970000") == .blockHeight(970_000))
        #expect(target("0840000") == nil)
        #expect(target("1000000", tip: nil) == .blockHeight(1_000_000))
        #expect(issue("1000000") == .futureBlock(height: 1_000_000, tip: 970_000))
    }

    @Test func datesAndTimestamps() {
        #expect(target("2009-01-03") == .timestamp(1_230_940_800))
        #expect(target("2009/1/3 18:15") == .timestamp(1_231_006_500))
        #expect(target("2009-01-03 18:15:05") == .timestamp(1_231_006_505))
        #expect(target("1231006505") == .timestamp(1_231_006_505))
        #expect(issue("2030-01-01") == .futureDate)
        #expect(issue("1999999999") == .futureDate)
        #expect(target("2024-02-30") == nil)
        #expect(target("2024-13-01") == nil)
    }

    @Test func secretsAreNeverTargets() {
        let xpub = "xpub" + String(repeating: "6CUGRUonZSQ4", count: 9)
        let xprv = "xprv" + String(repeating: "9s21ZrQH143K", count: 9)
        #expect(issue(xpub) == .extendedPublicKey)
        #expect(issue("zpub" + String(repeating: "6qUGRUonZSQ4", count: 9)) == .extendedPublicKey)
        #expect(issue(xprv) == .privateKey)
        #expect(issue("5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTJ") == .privateKey)
        #expect(issue("KwdMAjGmerYanjeui5SHS7JkmpZvVipYvB2LJGU1ZxJwYvP98617") == .privateKey)
        #expect(!SearchParser.interpret(xpub, tip: nil).allowsPrefixLookup)
        #expect(!SearchParser.interpret(xprv, tip: nil).allowsPrefixLookup)
    }

    @Test func otherNetworksPublicKeysAndLightning() {
        #expect(issue("tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx") == .otherNetwork("Testnet or signet"))
        #expect(issue("mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn") == .otherNetwork("Testnet or signet"))
        #expect(issue("02" + String(repeating: "ab", count: 32)) == .publicKey)
        #expect(issue("lightning:lnbc1u1p0abc") == .lightning)
    }

    @Test func paymentAndExplorerLinksAreCleaned() {
        #expect(SearchParser.clean("  bitcoin:\(Self.p2wpkh)?amount=0.01&label=x \n") == Self.p2wpkh)
        #expect(target("BITCOIN:\(Self.p2wpkh.uppercased())?amount=1") == .address(Self.p2wpkh))
        #expect(target("https://mempool.space/tx/\(Self.genesisTx)") == .transaction(txid: Self.genesisTx, output: nil))
        #expect(target("https://mempool.space/tx/\(Self.genesisTx)#vout=0") == .transaction(txid: Self.genesisTx, output: 0))
        #expect(target("https://mempool.space/block/840000") == .blockHeight(840_000))
        #expect(target("https://mempool.space/address/\(Self.taproot)") == .address(Self.taproot))
        #expect(target("https://mempool.space/testnet/tx/\(Self.genesisTx)") == nil)
    }

    @Test func unknownInput() {
        let r = SearchParser.interpret("hello world", tip: 1)
        #expect(r.target == nil && r.issue == nil)
        #expect(SearchParser.interpret("   ", tip: 1).query.isEmpty)
    }

    @Test func prefixLookupOnlyForAddressStarts() {
        #expect(SearchParser.interpret("bc1qxy2k", tip: 1).allowsPrefixLookup)
        #expect(SearchParser.interpret("1A1z", tip: 1).allowsPrefixLookup)
        #expect(!SearchParser.interpret("bc1", tip: 1).allowsPrefixLookup)
        #expect(!SearchParser.interpret("hello", tip: 1).allowsPrefixLookup)
        #expect(SearchParser.interpret("bc1qw508d6qejxtdg4y5", tip: 1).allowsPrefixLookup)  // half typed, no typo yet
        #expect(!SearchParser.interpret(Self.p2wpkh, tip: 1).allowsPrefixLookup)  // complete: goes straight there
    }

    @Test func futureBlockMessage() {
        let message = SearchIssue.futureBlock(height: 1_000_000, tip: 970_412).message
        #expect(message.contains("970,412"))
        #expect(message.contains("205 days"))
    }
}

@Suite struct ExploreRouteTests {
    let txid = SearchParserTests.genesisTx

    @Test func deepLinksRoundTrip() throws {
        let routes: [ExploreRoute] = [
            .transaction(txid, output: nil), .transaction(txid, output: 3), .block(.hash(SearchParserTests.genesisHash)), .block(.height(840_000)),
            .block(.timestamp(1_231_006_505)), .address(SearchParserTests.taproot), .pendingBlock(2), .latestBlocks,
        ]
        for route in routes {
            let link = try #require(route.deepLink)
            #expect(ExploreRoute(url: link) == route, "\(link)")
        }
    }

    @Test func addressLinksOnlyTakeAddressCharacters() {
        #expect(ExploreRoute(url: URL(string: "blockpulse://address/\(SearchParserTests.taproot)")!) == .address(SearchParserTests.taproot))
        let accented = "blockpulse://address/" + String(repeating: "é", count: 20)
        if let url = URL(string: accented) ?? URL(string: accented.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!) {
            #expect(ExploreRoute(url: url) == nil)
        }
    }

    @Test func webURLs() {
        let base = URL(string: "https://mempool.space/")!
        #expect(ExploreRoute.transaction(txid, output: nil).webURL(base: base)?.absoluteString == "https://mempool.space/tx/\(txid)")
        #expect(ExploreRoute.transaction(txid, output: 1).webURL(base: base)?.absoluteString == "https://mempool.space/tx/\(txid)#vout=1")
        #expect(ExploreRoute.block(.height(1)).webURL(base: base)?.absoluteString == "https://mempool.space/block/1")
        #expect(ExploreRoute.block(.timestamp(1)).webURL(base: base) == nil)
    }

    @Test func rejectsJunk() {
        #expect(ExploreRoute(url: URL(string: "blockpulse://tx/nothex")!) == nil)
        #expect(ExploreRoute(url: URL(string: "https://mempool.space/tx/\(txid)")!) == nil)
        #expect(ExploreRoute(webURL: "https://example.com/about") == nil)
    }
}

@Suite struct Bech32Tests {
    @Test func vectors() {
        #expect(Bech32.isValidAddress(SearchParserTests.p2wpkh, hrp: "bc"))
        #expect(Bech32.isValidAddress(SearchParserTests.p2wsh, hrp: "bc"))
        #expect(Bech32.isValidAddress(SearchParserTests.taproot, hrp: "bc"))
        #expect(!Bech32.isValidAddress(SearchParserTests.p2wpkh, hrp: "tb"))
        #expect(!Bech32.isValidAddress(SearchParserTests.p2wpkh.uppercased(), hrp: "bc"))
        #expect(!Bech32.isValidAddress("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kemeawh", hrp: "bc"))
    }
}

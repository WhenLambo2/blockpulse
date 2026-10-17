import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import BitcoinKit

@Suite struct ExploreModelsTests {
    /// Trimmed copy of an esplora transaction (extra fields the app ignores are left in).
    static let txJSON = """
    {"txid":"f4184fc596403b9d638783cf57adfe4c75c605f6356fbc91338530e9831e9e16","version":1,"locktime":0,
     "vin":[{"txid":"0437cd7f8525ceed2324359c2d0ba26006d92d856a9c20fa0241106ee5a597c9","vout":0,
             "prevout":{"scriptpubkey":"41","scriptpubkey_asm":"OP_PUSHBYTES_65","scriptpubkey_type":"p2pk","value":5000000000},
             "scriptsig":"47","scriptsig_asm":"","is_coinbase":false,"sequence":4294967295}],
     "vout":[{"scriptpubkey":"41","scriptpubkey_type":"p2pk","value":1000000000},
             {"scriptpubkey":"00","scriptpubkey_type":"v0_p2wpkh","scriptpubkey_address":"bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4","value":4000000000}],
     "size":275,"weight":1100,"sigops":8,"fee":0,
     "status":{"confirmed":true,"block_height":170,"block_hash":"00000000d1145790a8694403d4063f323d499e655c83426834d4ce2f8dd4a2ee","block_time":1231731025}}
    """

    @Test func decodesTransaction() throws {
        let tx = try JSONDecoder().decode(BitcoinTx.self, from: Data(Self.txJSON.utf8))
        #expect(tx.vsize == 275)
        #expect(tx.totalOutput == 5_000_000_000)
        #expect(tx.vin.first?.prevout?.scriptpubkeyAddress == nil)
        #expect(tx.vout[0].label == "Public key (P2PK)")
        #expect(tx.status.blockHeight == 170)
        #expect(tx.confirmations(tip: 179) == 10)
        #expect(!tx.signalsRBF && !tx.usesSegWit && !tx.usesTaproot && !tx.isCoinbase)
        #expect(tx.netValue(for: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4") == 4_000_000_000)
    }

    @Test func decodesPendingCoinbaseAndRBF() throws {
        let json = """
        {"txid":"aa","size":200,"weight":561,"fee":1000,
         "vin":[{"txid":"bb","vout":1,"prevout":{"scriptpubkey_type":"v1_p2tr","scriptpubkey_address":"bc1pme","value":5000},
                 "witness":["00"],"is_coinbase":false,"sequence":4294967293}],
         "vout":[{"scriptpubkey_type":"v0_p2wpkh","scriptpubkey_address":"bc1qyou","value":3000},
                 {"scriptpubkey_type":"op_return","value":0}],
         "status":{"confirmed":false}}
        """
        let tx = try JSONDecoder().decode(BitcoinTx.self, from: Data(json.utf8))
        #expect(tx.vsize == 141)
        #expect(tx.feeRate.map { ($0 * 100).rounded() / 100 } == 7.09)
        #expect(tx.signalsRBF && tx.usesSegWit && tx.usesTaproot)
        #expect(tx.netValue(for: "bc1pme") == -5_000)
        #expect(tx.confirmations(tip: 900_000) == nil)
        #expect(tx.vout[1].label == "OP_RETURN data")
    }

    @Test func decodesAddress() throws {
        let json = """
        {"address":"bc1qme","chain_stats":{"funded_txo_count":5,"funded_txo_sum":120,"spent_txo_count":3,"spent_txo_sum":100,"tx_count":7},
         "mempool_stats":{"funded_txo_count":1,"funded_txo_sum":42,"spent_txo_count":0,"spent_txo_sum":0,"tx_count":1}}
        """
        let a = try JSONDecoder().decode(AddressInfo.self, from: Data(json.utf8))
        #expect(a.balance == 20)
        #expect(a.pendingChange == 42)
        #expect(a.txCount == 8)
        #expect(a.unspentCount == 3)
        #expect(a.totalReceived == 162)
    }

    @Test func decodesSmallEndpoints() throws {
        let rbf = try JSONDecoder().decode(RBFInfo.self, from: Data(#"{"replacements":{"tx":{"txid":"new","fee":1},"time":1,"replaces":[]},"replaces":null}"#.utf8))
        #expect(rbf.replacement(of: "old") == "new")
        #expect(rbf.replacement(of: "new") == nil)
        let empty = try JSONDecoder().decode(RBFInfo.self, from: Data(#"{"replacements":null,"replaces":null}"#.utf8))
        #expect(empty.replacement(of: "x") == nil)
        let cpfp = try JSONDecoder().decode(CPFPInfo.self, from: Data(#"{"ancestors":[],"effectiveFeePerVsize":12.5}"#.utf8))
        #expect(cpfp.effectiveFeePerVsize == 12.5)
        let at = try JSONDecoder().decode(BlockAtTime.self, from: Data(#"{"height":1,"hash":"00ab","timestamp":"2009-01-09T02:54:25.000Z"}"#.utf8))
        #expect(at.height == 1)
        let outspends = try JSONDecoder().decode([Outspend].self, from: Data(#"[{"spent":true,"txid":"cc","vin":0,"status":{"confirmed":true}},{"spent":false}]"#.utf8))
        #expect(outspends.map(\.spent) == [true, false])
    }

    @Test func addressKinds() {
        #expect(AddressKind(SearchParserTests.taproot) == .taproot)
        #expect(AddressKind(SearchParserTests.p2wpkh) == .nativeSegWit)
        #expect(AddressKind(SearchParserTests.p2wsh) == .nativeSegWitScript)
        #expect(AddressKind("3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy") == .nestedOrScript)
        #expect(AddressKind("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa") == .legacy)
    }

    @Test func pendingPosition() {
        let blocks = [6.0, 4.0, 3.0].map {
            ProjectedBlock(blockSize: 1, blockVSize: 1, nTx: 1, totalFees: 1, medianFee: $0, feeRange: [$0, $0 * 2])
        }
        #expect(PendingPosition.blockIndex(feeRate: 12, projected: blocks) == 0)
        #expect(PendingPosition.blockIndex(feeRate: 4.5, projected: blocks) == 1)
        #expect(PendingPosition.blockIndex(feeRate: 1, projected: blocks) == nil)
        #expect(PendingPosition.minutes(index: 1) == 20)
    }

    @Test func btcFormatting() {
        #expect(Format.btc(4_250_000) == "0.0425 BTC")
        #expect(Format.btc(5_000_000_000) == "50.00 BTC")
        #expect(Format.btc(1) == "0.00000001 BTC")
        #expect(Format.btc(-21_000_000, signed: true) == "-0.21 BTC")
        #expect(Format.btc(21_000_000, signed: true) == "+0.21 BTC")
        #expect(Format.btc(123_456_789_000) == "1,234.56789 BTC")
        #expect(Format.short("f4184fc596403b9d638783cf57adfe4c75c605f6356fbc91338530e9831e9e16") == "f4184fc5…1e9e16")
        #expect(Format.fiat(4_250_000, price: 92_100, .eur) == "€3,914")
        #expect(Format.fiat(500, price: 92_100, .eur) == "€0.46")
    }
}

@Suite struct ExploreClientTests {
    let transport = FakeTransport()
    var client: MempoolClient { MempoolClient(transport: transport) }

    @Test func plainTextEndpoints() async throws {
        transport.stub("/api/blocks/tip/height", data: Data("970412\n".utf8))
        #expect(try await client.tipHeight() == 970_412)
        let hash = SearchParserTests.genesisHash
        transport.stub("/api/block-height/0", data: Data(hash.utf8))
        #expect(try await client.blockHash(height: 0) == hash)
        transport.stub("/api/block-height/1", data: Data("Block not found".utf8))
        await #expect(throws: MempoolError.self) { try await client.blockHash(height: 1) }
    }

    @Test func pathsAndNotFound() async throws {
        transport.stub("/api/address-prefix/bc1qxy2k", data: Data(#"["bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"]"#.utf8))
        #expect(try await client.addressPrefix("BC1QXY2K").count == 1)
        transport.stub("/api/tx/missing", status: 404, data: Data("Transaction not found".utf8))
        do {
            _ = try await client.transaction("missing")
            Issue.record("expected a 404")
        } catch let error as MempoolError {
            #expect(error.isNotFound)
        }
        _ = try? await client.addressTransactions("bc1qme", after: "abc")
        #expect(transport.requests.last?.url?.path == "/api/address/bc1qme/txs/chain/abc")
        _ = try? await client.blockTransactions("00ab", start: 25)
        #expect(transport.requests.last?.url?.path == "/api/block/00ab/txs/25")
        _ = try? await client.blocks(endingAt: 900_000)
        #expect(transport.requests.last?.url?.path == "/api/v1/blocks/900000")
    }
}

@Suite struct MempoolOverviewTests {
    @Test func feeBands() throws {
        let json = #"{"count":3,"vsize":600,"total_fee":900,"fee_histogram":[[25.5,100],[10,50],[4.2,150],[1.5,200],[0.3,100]]}"#
        let backlog = try JSONDecoder().decode(MempoolBacklog.self, from: Data(json.utf8))
        let bands = backlog.bands()
        #expect(bands.map(\.label) == ["<1", "1–2", "2–4", "4–10", "10+"])
        #expect(bands.map(\.vsize) == [100, 200, 0, 150, 150])
        #expect(backlog.blocksToClear == 1)
    }

    @Test func histogramIsOptional() throws {
        let backlog = try JSONDecoder().decode(MempoolBacklog.self, from: Data(#"{"count":1,"vsize":2}"#.utf8))
        #expect(backlog.feeHistogram.isEmpty)
        #expect(backlog.bands().allSatisfy { $0.vsize == 0 })
    }

    @Test func recentTransactions() throws {
        let json = #"[{"txid":"ab","fee":420,"vsize":140.25,"value":125000}]"#
        let txs = try JSONDecoder().decode([RecentMempoolTx].self, from: Data(json.utf8))
        #expect(txs.first?.value == 125_000)
        #expect(abs((txs.first?.feeRate ?? 0) - 2.9946) < 0.001)
    }

    @Test func cancelledRequestsAreNotNetworkErrors() async {
        let transport = FakeTransport()
        transport.failure = URLError(.cancelled)
        await #expect(throws: CancellationError.self) { try await MempoolClient(transport: transport).tipHeight() }
    }

    @Test func userInputInPathsIsEncoded() {
        let request = MempoolClient(transport: FakeTransport()).makeRequest(path: "/api/address/éé")
        #expect(request.url?.absoluteString.hasSuffix("/api/address/%C3%A9%C3%A9") == true)
    }
}

@Suite struct RecentSearchesTests {
    let defaults = UserDefaults(suiteName: "blockpulse-recent-\(UUID().uuidString)")!
    var prefs: AppPreferences { AppPreferences(defaults: defaults) }

    @Test func newestFirstDedupedAndCapped() {
        prefs.remember(.block(.height(1)))
        prefs.remember(.address(SearchParserTests.taproot))
        prefs.remember(.block(.height(1)))
        #expect(prefs.recentSearches == [.block(.height(1)), .address(SearchParserTests.taproot)])
        for h in 10..<30 { prefs.remember(.block(.height(h))) }
        #expect(prefs.recentSearches.count == AppPreferences.recentSearchLimit)
        #expect(prefs.recentSearches.first == .block(.height(29)))
    }

    @Test func switchingOffClearsAndStops() {
        #expect(prefs.remembersSearches)
        prefs.remember(.block(.height(1)))
        prefs.remembersSearches = false
        #expect(prefs.recentSearches.isEmpty)
        prefs.remember(.block(.height(2)))
        #expect(prefs.recentSearches.isEmpty)
    }
}

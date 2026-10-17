import Foundation

/// GET /api/tx/:txid (also the elements of block and address transaction lists).
/// Named `BitcoinTx` so it never clashes with SwiftUI's `Transaction`.
public struct BitcoinTx: Codable, Sendable, Equatable, Identifiable {
    public let txid: String
    public let version: Int?
    public let locktime: Int?
    public let size: Int
    public let weight: Int
    /// Sats; 0 for a coinbase.
    public let fee: Int?
    public let vin: [TxInput]
    public let vout: [TxOutput]
    public let status: TxStatus

    public init(txid: String, version: Int? = 2, locktime: Int? = 0, size: Int, weight: Int, fee: Int?,
                vin: [TxInput], vout: [TxOutput], status: TxStatus) {
        self.txid = txid; self.version = version; self.locktime = locktime; self.size = size; self.weight = weight
        self.fee = fee; self.vin = vin; self.vout = vout; self.status = status
    }

    public var id: String { txid }
    public var vsize: Int { (weight + 3) / 4 }
    public var feeRate: Double? { fee.map { Double($0) / Double(max(vsize, 1)) } }
    public var totalOutput: Int { vout.reduce(0) { $0 + $1.value } }
    public var isCoinbase: Bool { vin.first?.isCoinbase == true }
    /// Opts in to replace-by-fee (BIP125): any input sequence below 0xfffffffe.
    public var signalsRBF: Bool { vin.contains { ($0.sequence ?? 0xffffffff) < 0xfffffffe } }
    public var usesSegWit: Bool { vin.contains { !($0.witness ?? []).isEmpty } }
    public var usesTaproot: Bool {
        vin.contains { $0.prevout?.scriptpubkeyType == "v1_p2tr" } || vout.contains { $0.scriptpubkeyType == "v1_p2tr" }
    }

    /// What this transaction did to `address`, in sats: received minus spent.
    public func netValue(for address: String) -> Int {
        let received = vout.filter { $0.scriptpubkeyAddress == address }.reduce(0) { $0 + $1.value }
        let spent = vin.compactMap(\.prevout).filter { $0.scriptpubkeyAddress == address }.reduce(0) { $0 + $1.value }
        return received - spent
    }

    public func confirmations(tip: Int?) -> Int? {
        guard status.confirmed, let height = status.blockHeight, let tip, tip >= height else { return nil }
        return tip - height + 1
    }
}

public struct TxInput: Codable, Sendable, Equatable {
    public let txid: String
    public let vout: Int
    /// Nil for a coinbase input.
    public let prevout: TxOutput?
    public let witness: [String]?
    public let isCoinbase: Bool
    public let sequence: Int?

    public init(txid: String, vout: Int, prevout: TxOutput?, witness: [String]? = nil, isCoinbase: Bool = false, sequence: Int? = 0xffffffff) {
        self.txid = txid; self.vout = vout; self.prevout = prevout; self.witness = witness
        self.isCoinbase = isCoinbase; self.sequence = sequence
    }

    enum CodingKeys: String, CodingKey {
        case txid, vout, prevout, witness, sequence
        case isCoinbase = "is_coinbase"
    }
}

public struct TxOutput: Codable, Sendable, Equatable {
    public let scriptpubkeyType: String?
    /// Nil for outputs without an address (OP_RETURN, bare multisig).
    public let scriptpubkeyAddress: String?
    public let value: Int

    public init(scriptpubkeyType: String?, scriptpubkeyAddress: String?, value: Int) {
        self.scriptpubkeyType = scriptpubkeyType; self.scriptpubkeyAddress = scriptpubkeyAddress; self.value = value
    }

    /// "OP_RETURN", "Bare multisig"... for outputs without an address.
    public var label: String {
        if let scriptpubkeyAddress { return scriptpubkeyAddress }
        switch scriptpubkeyType {
        case "op_return": return "OP_RETURN data"
        case "multisig": return "Bare multisig"
        case "p2pk": return "Public key (P2PK)"
        default: return "Unknown script"
        }
    }

    enum CodingKeys: String, CodingKey {
        case value
        case scriptpubkeyType = "scriptpubkey_type"
        case scriptpubkeyAddress = "scriptpubkey_address"
    }
}

public struct TxStatus: Codable, Sendable, Equatable {
    public let confirmed: Bool
    public let blockHeight: Int?
    public let blockHash: String?
    public let blockTime: Int?

    public init(confirmed: Bool, blockHeight: Int? = nil, blockHash: String? = nil, blockTime: Int? = nil) {
        self.confirmed = confirmed; self.blockHeight = blockHeight; self.blockHash = blockHash; self.blockTime = blockTime
    }

    public var blockDate: Date? { blockTime.map { Date(timeIntervalSince1970: TimeInterval($0)) } }

    enum CodingKeys: String, CodingKey {
        case confirmed
        case blockHeight = "block_height"
        case blockHash = "block_hash"
        case blockTime = "block_time"
    }
}

/// Element of GET /api/tx/:txid/outspends.
public struct Outspend: Codable, Sendable, Equatable {
    public let spent: Bool
    public let txid: String?

    public init(spent: Bool, txid: String?) { self.spent = spent; self.txid = txid }
}

/// GET /api/v1/cpfp/:txid. Only the effective fee rate is used (it includes parents and children).
public struct CPFPInfo: Codable, Sendable, Equatable {
    public let effectiveFeePerVsize: Double?
    public init(effectiveFeePerVsize: Double?) { self.effectiveFeePerVsize = effectiveFeePerVsize }
}

/// GET /api/v1/tx/:txid/rbf. `replacements` is a tree whose root is the latest version.
public struct RBFInfo: Codable, Sendable, Equatable {
    public struct Node: Codable, Sendable, Equatable {
        public struct Tx: Codable, Sendable, Equatable { public let txid: String }
        public let tx: Tx
    }

    public let replacements: Node?
    public let replaces: [String]?

    public init(replacements: Node?, replaces: [String]?) { self.replacements = replacements; self.replaces = replaces }

    /// The transaction that replaced `txid`, when it was replaced.
    public func replacement(of txid: String) -> String? {
        guard let latest = replacements?.tx.txid, latest != txid else { return nil }
        return latest
    }
}

/// GET /api/address/:address
public struct AddressInfo: Codable, Sendable, Equatable {
    public struct Stats: Codable, Sendable, Equatable {
        public let fundedTxoCount: Int
        public let fundedTxoSum: Int
        public let spentTxoCount: Int
        public let spentTxoSum: Int
        public let txCount: Int

        public init(fundedTxoCount: Int, fundedTxoSum: Int, spentTxoCount: Int, spentTxoSum: Int, txCount: Int) {
            self.fundedTxoCount = fundedTxoCount; self.fundedTxoSum = fundedTxoSum
            self.spentTxoCount = spentTxoCount; self.spentTxoSum = spentTxoSum; self.txCount = txCount
        }

        public var balance: Int { fundedTxoSum - spentTxoSum }
        public var unspentCount: Int { fundedTxoCount - spentTxoCount }

        enum CodingKeys: String, CodingKey {
            case fundedTxoCount = "funded_txo_count"
            case fundedTxoSum = "funded_txo_sum"
            case spentTxoCount = "spent_txo_count"
            case spentTxoSum = "spent_txo_sum"
            case txCount = "tx_count"
        }
    }

    public let address: String
    public let chainStats: Stats
    public let mempoolStats: Stats

    public init(address: String, chainStats: Stats, mempoolStats: Stats) {
        self.address = address; self.chainStats = chainStats; self.mempoolStats = mempoolStats
    }

    /// Confirmed balance, sats.
    public var balance: Int { chainStats.balance }
    /// Change waiting in the mempool, sats (can be negative).
    public var pendingChange: Int { mempoolStats.balance }
    public var txCount: Int { chainStats.txCount + mempoolStats.txCount }
    public var totalReceived: Int { chainStats.fundedTxoSum + mempoolStats.fundedTxoSum }
    public var totalSent: Int { chainStats.spentTxoSum + mempoolStats.spentTxoSum }
    public var unspentCount: Int { chainStats.unspentCount + mempoolStats.unspentCount }

    enum CodingKeys: String, CodingKey {
        case address
        case chainStats = "chain_stats"
        case mempoolStats = "mempool_stats"
    }
}

/// GET /api/v1/mining/blocks/timestamp/:timestamp (the `timestamp` field, an ISO string, is ignored).
public struct BlockAtTime: Codable, Sendable, Equatable {
    public let height: Int
    public let hash: String
    public init(height: Int, hash: String) { self.height = height; self.hash = hash }
}

/// Address kind from its format, for the label on the address page.
public enum AddressKind: Sendable, Equatable {
    case taproot, nativeSegWit, nativeSegWitScript, nestedOrScript, legacy, other

    public init(_ address: String) {
        let a = address.lowercased()
        if a.hasPrefix("bc1p") { self = .taproot }
        else if a.hasPrefix("bc1q") { self = a.count == 42 ? .nativeSegWit : .nativeSegWitScript }
        else if a.hasPrefix("3") { self = .nestedOrScript }
        else if a.hasPrefix("1") { self = .legacy }
        else { self = .other }
    }

    public var label: String {
        switch self {
        case .taproot: "Taproot"
        case .nativeSegWit: "Native SegWit"
        case .nativeSegWitScript: "Native SegWit script"
        case .nestedOrScript: "Nested SegWit or script"
        case .legacy: "Legacy"
        case .other: "Address"
        }
    }
}

/// Where a pending transaction sits in the projected blocks, the way mempool.space estimates it:
/// the first projected block whose lowest fee rate it beats.
public enum PendingPosition {
    /// 0-based index of the projected block, or nil when it is beyond all of them.
    public static func blockIndex(feeRate: Double, projected: [ProjectedBlock]) -> Int? {
        guard !projected.isEmpty else { return nil }
        if let i = projected.firstIndex(where: { feeRate >= $0.minFee }) { return i }
        return nil
    }

    /// Minutes until the block at `index` is likely mined.
    public static func minutes(index: Int) -> Int { (index + 1) * 10 }
}

extension Format {
    /// Sats as BTC: "0.0425 BTC", up to 8 decimals with trailing zeros trimmed (at least 2).
    public static func btc(_ sats: Int, signed: Bool = false) -> String {
        let sign = signed ? (sats > 0 ? "+" : sats < 0 ? "-" : "") : (sats < 0 ? "-" : "")
        let whole = abs(sats) / 100_000_000
        var fraction = String(format: "%08ld", abs(sats) % 100_000_000)
        while fraction.count > 2 && fraction.hasSuffix("0") { fraction.removeLast() }
        return sign + grouped(Double(whole)) + "." + fraction + " BTC"
    }

    /// "f4184fc5…a19e16": the start and end of a long id.
    public static func short(_ id: String, head: Int = 8, tail: Int = 6) -> String {
        guard id.count > head + tail + 1 else { return id }
        return String(id.prefix(head)) + "…" + String(id.suffix(tail))
    }

    /// Fiat value of `sats`: "€3,914" (or "€0.42" below 10).
    public static func fiat(_ sats: Int, price: Double, _ currency: Currency) -> String {
        let value = Double(abs(sats)) / 100_000_000 * price
        let sign = sats < 0 ? "-" : ""
        return sign + currency.symbol + (value < 10 ? String(format: "%.2f", value) : grouped(value))
    }
}

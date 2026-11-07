import Foundation

/// Where a search lands. Mirrors mempool.space's search: the same input opens the same kind of page.
public enum SearchTarget: Hashable, Sendable {
    case address(String)
    case blockHash(String)
    case blockHeight(Int)
    /// `output` comes from a `txid:n` search and highlights that output.
    case transaction(txid: String, output: Int?)
    /// A date or Unix timestamp; opens the block mined at or just before it.
    case timestamp(Int)

    /// The heading mempool.space shows above the "Go to" row.
    public var title: String {
        switch self {
        case .address: "Bitcoin address"
        case .blockHash: "Bitcoin block"
        case .blockHeight: "Bitcoin block height"
        case .transaction: "Bitcoin transaction"
        case .timestamp: "Block at a date"
        }
    }

    public var route: ExploreRoute {
        switch self {
        case .address(let a): .address(a)
        case .blockHash(let h): .block(.hash(h))
        case .blockHeight(let h): .block(.height(h))
        case .transaction(let txid, let output): .transaction(txid, output: output)
        case .timestamp(let t): .block(.timestamp(t))
        }
    }
}

/// Inputs that are recognised but can't be opened, each with its own explanation.
public enum SearchIssue: Hashable, Sendable {
    /// Height above the current tip.
    case futureBlock(height: Int, tip: Int)
    case futureDate
    /// xpub, ypub, zpub and friends: never sent to a server.
    case extendedPublicKey
    /// xprv or WIF: never sent anywhere, with a warning.
    case privateKey
    /// Right shape, wrong checksum.
    case addressTypo
    /// Testnet, signet or regtest address.
    case otherNetwork(String)
    case publicKey
    case lightning

    public var title: String {
        switch self {
        case .futureBlock(let height, _): "Block \(Format.grouped(Double(height))) isn't mined yet"
        case .futureDate: "That moment is still to come"
        case .extendedPublicKey: "Extended public keys stay private"
        case .privateKey: "This looks like a private key"
        case .addressTypo: "This address has a typo"
        case .otherNetwork(let network): "\(network) address"
        case .publicKey: "Public keys aren't supported yet"
        case .lightning: "Lightning isn't supported"
        }
    }

    public var message: String {
        switch self {
        case .futureBlock(let height, let tip):
            let blocks = height - tip
            let days = Double(blocks) * 600 / 86_400
            let when = days < 1 ? "about \(max(1, Int((Double(blocks) * 10 / 60).rounded()))) hours away"
                : "about \(Format.grouped(days.rounded())) days away"
            return "The chain is at \(Format.grouped(Double(tip))). At 10 minutes per block that's \(when)."
        case .futureDate:
            return "Search for a date or time in the past to see the block mined then."
        case .extendedPublicKey:
            return "An xpub reveals every address in a wallet, so Blockpulse never sends it to a server. Search one address at a time, or use a watch-only wallet."
        case .privateKey:
            return "Anyone with it can spend the coins. Blockpulse didn't send it anywhere. Don't paste it into other apps or sites."
        case .addressTypo:
            return "The checksum doesn't match, so at least one character is wrong. Check it against the original."
        case .otherNetwork:
            return "Blockpulse shows the main Bitcoin network only."
        case .publicKey:
            return "Search the address that belongs to this key instead."
        case .lightning:
            return "Blockpulse shows the Bitcoin blockchain only. Open Lightning invoices in a Lightning wallet."
        }
    }
}

public struct SearchInterpretation: Equatable, Sendable {
    /// The input after cleaning (trimmed, payment link and web link removed).
    public let query: String
    public let target: SearchTarget?
    public let issue: SearchIssue?

    /// Whether the address prefix lookup may be sent for this input.
    public var allowsPrefixLookup: Bool { target == nil && issue == nil && SearchParser.looksLikeAddressPrefix(query) }
}

/// Recognises what was typed, pasted or scanned, in the same order as mempool.space's search
/// (frontend `search-form.component.ts` and `shared/regex.utils.ts`).
public enum SearchParser {
    static let base58 = "[a-km-zA-HJ-NP-Z1-9]"
    static let bech32Lower = "[ac-hj-np-z02-9]"
    static let bech32Upper = "[AC-HJ-NP-Z02-9]"

    nonisolated(unsafe) static let blockHeight = regex("^(?:0|[1-9][0-9]{0,8})$")
    /// 64 hex starting with 8 zeros (at least 32 bits of work). Tested before transactions.
    nonisolated(unsafe) static let blockHash = regex("^0{8}[a-fA-F0-9]{56}$")
    nonisolated(unsafe) static let transaction = regex("^([a-fA-F0-9]{64})(?::(0|[1-9][0-9]{0,8}))?$")
    nonisolated(unsafe) static let mainnetBase58 = regex("^[13]\(base58){26,33}$")
    nonisolated(unsafe) static let mainnetBech32 = regex("^(?:bc1\(bech32Lower){6,100}|BC1\(bech32Upper){6,100})$")
    nonisolated(unsafe) static let testnetBase58 = regex("^[mn2]\(base58){33,34}$")
    nonisolated(unsafe) static let testnetBech32 = regex("^(?:tb1\(bech32Lower){6,100}|TB1\(bech32Upper){6,100})$")
    nonisolated(unsafe) static let regtestBech32 = regex("^(?:bcrt1\(bech32Lower){6,100}|BCRT1\(bech32Upper){6,100})$")
    nonisolated(unsafe) static let publicKey = regex("^(?:04[a-fA-F0-9]{128}|0[23][a-fA-F0-9]{64})$")
    nonisolated(unsafe) static let date = regex("^[0-9]{4}[-/][0-9]{1,2}[-/][0-9]{1,2}(?: [0-9]{1,2}:[0-9]{1,2}(?::[0-9]{1,2})?)?$")
    nonisolated(unsafe) static let unixTimestamp = regex("^[0-9]{10}$")
    nonisolated(unsafe) static let extendedPublicKey = regex("^[xyzYZtuvUV]pub\(base58){100,112}$")
    nonisolated(unsafe) static let extendedPrivateKey = regex("^[xyzYZtuvUV]prv\(base58){100,112}$")
    nonisolated(unsafe) static let wif = regex("^(?:5\(base58){50}|[KL]\(base58){51})$")
    nonisolated(unsafe) static let addressPrefix = regex("^(?:bc1\(bech32Lower){1,100}|BC1\(bech32Upper){1,100}|[13]\(base58){1,33})$")

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns above are constants; a typo would show up in every test.
        try! NSRegularExpression(pattern: pattern)
    }

    static func matches(_ regex: NSRegularExpression, _ s: String) -> Bool {
        regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// `tip`: current block height, when known (heights above it can't be opened).
    public static func interpret(_ raw: String, tip: Int?, now: Date = Date(), timeZone: TimeZone = .current) -> SearchInterpretation {
        let query = clean(raw)
        func result(_ target: SearchTarget?, _ issue: SearchIssue? = nil) -> SearchInterpretation {
            SearchInterpretation(query: query, target: target, issue: issue)
        }
        guard !query.isEmpty else { return result(nil) }
        if query.lowercased().hasPrefix("lightning:") || query.lowercased().hasPrefix("lnbc") { return result(nil, .lightning) }
        if matches(extendedPrivateKey, query) || matches(wif, query) { return result(nil, .privateKey) }
        if matches(extendedPublicKey, query) { return result(nil, .extendedPublicKey) }

        let isTransactionShape = matches(transaction, query)
        // 1. Address (never when it's also 64 hex).
        if !isTransactionShape {
            if matches(mainnetBase58, query) { return result(.address(query)) }
            if matches(mainnetBech32, query) {
                let address = query.lowercased()
                if Bech32.isValidAddress(address, hrp: "bc") { return result(.address(address)) }
                // Complete addresses are 42 (SegWit v0 key) or 62 (script, Taproot) long; shorter is still being typed.
                if address.count == 42 || address.count >= 62 { return result(nil, .addressTypo) }
                return result(nil)
            }
            if matches(publicKey, query) { return result(nil, .publicKey) }
        }
        // 2. Block hash, before transactions.
        if matches(blockHash, query) { return result(.blockHash(query.lowercased())) }
        // 3. Block height, up to the tip.
        if matches(blockHeight, query), let height = Int(query) {
            if let tip, height > tip { return result(nil, .futureBlock(height: height, tip: tip)) }
            return result(.blockHeight(height))
        }
        // 4. Transaction, optionally with an output.
        if let m = transaction.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
           let idRange = Range(m.range(at: 1), in: query) {
            let output = Range(m.range(at: 2), in: query).flatMap { Int(query[$0]) }
            return result(.transaction(txid: query[idRange].lowercased(), output: output))
        }
        // 5. Date, 6. Unix timestamp.
        if matches(date, query) {
            guard let seconds = parseDate(query, timeZone: timeZone) else { return result(nil) }
            return seconds > Int(now.timeIntervalSince1970) ? result(nil, .futureDate) : result(.timestamp(seconds))
        }
        if matches(unixTimestamp, query), let seconds = Int(query) {
            return seconds > Int(now.timeIntervalSince1970) ? result(nil, .futureDate) : result(.timestamp(seconds))
        }
        if matches(testnetBech32, query) || matches(testnetBase58, query) { return result(nil, .otherNetwork("Testnet or signet")) }
        if matches(regtestBech32, query) { return result(nil, .otherNetwork("Regtest")) }
        return result(nil)
    }

    /// Trims, and reduces payment links (`bitcoin:addr?amount=…`) and explorer links
    /// (`https://mempool.space/tx/…`) to what they point at.
    public static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("bitcoin:") {
            s = String(s.dropFirst("bitcoin:".count))
            if let q = s.firstIndex(of: "?") { s = String(s[..<q]) }
            if s.hasPrefix("//") { s = String(s.dropFirst(2)) }
            return s
        }
        if let route = ExploreRoute(webURL: s) { return route.searchText }
        return s
    }

    /// Mainnet address start that may be sent for suggestions (from four characters, nothing secret-looking).
    public static func looksLikeAddressPrefix(_ s: String) -> Bool {
        s.count >= 4 && matches(addressPrefix, s)
    }

    /// `2024-01-03`, `2024/1/3 14:05`, `2024-01-03 14:05:09` in `timeZone`.
    static func parseDate(_ s: String, timeZone: TimeZone) -> Int? {
        let parts = s.split(separator: " ")
        let day = parts[0].split(whereSeparator: { $0 == "-" || $0 == "/" }).compactMap { Int($0) }
        guard day.count == 3 else { return nil }
        let time = parts.count > 1 ? parts[1].split(separator: ":").compactMap { Int($0) } : []
        var c = DateComponents()
        c.year = day[0]; c.month = day[1]; c.day = day[2]
        c.hour = time.count > 0 ? time[0] : 0
        c.minute = time.count > 1 ? time[1] : 0
        c.second = time.count > 2 ? time[2] : 0
        guard (1...12).contains(day[1]), (1...31).contains(day[2]),
              (0...23).contains(c.hour!), (0...59).contains(c.minute!), (0...59).contains(c.second!) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = calendar.date(from: c), calendar.component(.day, from: date) == day[2] else { return nil }
        return Int(date.timeIntervalSince1970)
    }
}

/// BIP173 / BIP350 checksums for SegWit addresses, checked on the phone before anything is sent.
public enum Bech32 {
    static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    static let generator: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]

    static func polymod(_ values: [UInt8]) -> UInt32 {
        var chk: UInt32 = 1
        for v in values {
            let top = chk >> 25
            chk = ((chk & 0x1ffffff) << 5) ^ UInt32(v)
            for i in 0..<5 where (top >> UInt32(i)) & 1 == 1 { chk ^= generator[i] }
        }
        return chk
    }

    static func expand(_ hrp: String) -> [UInt8] {
        let bytes = Array(hrp.utf8)
        return bytes.map { $0 >> 5 } + [0] + bytes.map { $0 & 31 }
    }

    /// Lowercase SegWit address for `hrp` with a valid checksum of the right variant
    /// (bech32 for version 0, bech32m for 1 and up) and a valid program length.
    public static func isValidAddress(_ address: String, hrp: String) -> Bool {
        guard address == address.lowercased(), address.count <= 90,
              let separator = address.lastIndex(of: "1"),
              String(address[..<separator]) == hrp else { return false }
        let dataPart = address[address.index(after: separator)...]
        var values: [UInt8] = []
        for ch in dataPart {
            guard let i = charset.firstIndex(of: ch) else { return false }
            values.append(UInt8(i))
        }
        guard values.count >= 7 else { return false }
        let check = polymod(expand(hrp) + values)
        let version = values[0]
        guard version <= 16 else { return false }
        let expected: UInt32 = version == 0 ? 1 : 0x2bc830a3
        guard check == expected else { return false }
        guard let program = convertBits(Array(values.dropFirst().dropLast(6)), from: 5, to: 8) else { return false }
        if version == 0 { return program.count == 20 || program.count == 32 }
        return (2...40).contains(program.count)
    }

    static func convertBits(_ data: [UInt8], from: Int, to: Int) -> [UInt8]? {
        var acc = 0, bits = 0
        var out: [UInt8] = []
        let maxv = (1 << to) - 1
        let maxAcc = (1 << (from + to - 1)) - 1
        for value in data {
            acc = ((acc << from) | Int(value)) & maxAcc
            bits += from
            while bits >= to {
                bits -= to
                out.append(UInt8((acc >> bits) & maxv))
            }
        }
        guard bits < from, (acc << (to - bits)) & maxv == 0 else { return nil }
        return out
    }
}

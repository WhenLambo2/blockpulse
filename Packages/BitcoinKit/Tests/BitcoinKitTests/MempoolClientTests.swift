import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import BitcoinKit

@Suite struct MempoolClientTests {
    let transport = FakeTransport()
    var client: MempoolClient { MempoolClient(transport: transport) }

    @Test func defaultBaseURLIsPublicMempool() {
        #expect(MempoolClient.defaultBaseURL.absoluteString == "https://mempool.space")
    }

    @Test func buildsGETWithHeadersAndNoAuthByDefault() async throws {
        try transport.stub("/api/v1/prices", fixture: "prices")
        _ = try await client.prices()
        let req = try #require(transport.requests.first)
        #expect(req.url?.absoluteString == "https://mempool.space/api/v1/prices")
        #expect(req.httpMethod == "GET")
        #expect(req.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(req.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Blockpulse/") == true)
        #expect(req.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(req.timeoutInterval == 10)
    }

    @Test func sendsAuthorizationWhenConfigured() async throws {
        try transport.stub("/api/v1/prices", fixture: "prices")
        _ = try await MempoolClient(authorization: "Bearer abc", transport: transport).prices()
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
    }

    @Test func blankAuthorizationIsOmitted() async throws {
        try transport.stub("/api/v1/prices", fixture: "prices")
        _ = try await MempoolClient(authorization: "   ", transport: transport).prices()
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func trailingSlashBaseURLDoesNotDoubleSlash() {
        let c = MempoolClient(baseURL: URL(string: "https://example.org/")!, transport: transport)
        #expect(c.makeRequest(path: "/api/mempool").url?.absoluteString == "https://example.org/api/mempool")
    }

    @Test func historicalPriceQuery() async throws {
        try transport.stub("/api/v1/historical-price", fixture: "historical-price")
        _ = try await client.historicalPrice(at: Date(timeIntervalSince1970: 1_791_755_726), currency: .eur)
        let url = try #require(transport.requests.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "currency", value: "EUR")))
        #expect(items.contains(URLQueryItem(name: "timestamp", value: "1791755726")))
    }

    @Test func allEndpointsDecode() async throws {
        try transport.stubAllFixtures()
        #expect(try await client.recentBlocks().count == 15)
        #expect(try await client.recommendedFees().fastestFee >= 0)
        #expect(try await client.mempool().count > 0)
        #expect(try await client.difficultyAdjustment().remainingBlocks > 0)
    }

    @Test func recommendedFeesUsesPreciseEndpointAndKeepsFractions() async throws {
        try transport.stub("/api/v1/fees/precise", fixture: "fees-precise")
        let fees = try await client.recommendedFees()
        #expect(transport.requests.first?.url?.path == "/api/v1/fees/precise")
        #expect(fees.economyFee == 0.2)
        #expect(fees.hourFee == 0.249)
        #expect(fees.minimumFee < 1)
    }

    @Test(arguments: [(401, MempoolError.unauthorized), (403, .unauthorized), (429, .rateLimited), (500, .http(500)), (404, .http(404))])
    func mapsStatusCodes(status: Int, expected: MempoolError) async {
        transport.stub("/api/v1/prices", status: status, data: Data())
        await #expect(throws: expected) { try await client.prices() }
    }

    @Test func mapsGarbageToDecoding() async {
        transport.stub("/api/v1/prices", data: Data("<html>".utf8))
        do {
            _ = try await client.prices()
            Issue.record("expected throw")
        } catch let error as MempoolError {
            guard case .decoding = error else { Issue.record("got \(error)"); return }
        } catch { Issue.record("wrong error type \(error)") }
    }

    @Test func mapsTransportErrorToNetwork() async {
        transport.failure = URLError(.notConnectedToInternet)
        do {
            _ = try await client.prices()
            Issue.record("expected throw")
        } catch let error as MempoolError {
            guard case .network = error else { Issue.record("got \(error)"); return }
        } catch { Issue.record("wrong error type \(error)") }
    }

    @Test func checkConnectionSuccess() async throws {
        try transport.stub("/api/v1/prices", fixture: "prices")
        let check = await client.checkConnection()
        #expect(check.succeeded)
        #expect(check.latencyMilliseconds >= 0)
        #expect(check.summary.hasPrefix("OK · "))
        #expect(check.summary.hasSuffix(" ms"))
    }

    @Test func checkConnectionFailure() async {
        transport.stub("/api/v1/prices", status: 429, data: Data())
        let check = await client.checkConnection()
        #expect(!check.succeeded)
        #expect(check.error == .rateLimited)
        #expect(check.summary == "Failed: Rate limited (HTTP 429)")
    }

    @Test func userMessages() {
        #expect(MempoolError.unauthorized.userMessage == "Access denied (HTTP 401/403)")
        #expect(MempoolError.rateLimited.userMessage == "Rate limited (HTTP 429)")
        #expect(MempoolError.http(502).userMessage == "Server error (HTTP 502)")
        #expect(MempoolError.network("offline").userMessage == "Network error: offline")
        #expect(MempoolError.decoding("x").userMessage == "Unexpected response from server")
    }
}

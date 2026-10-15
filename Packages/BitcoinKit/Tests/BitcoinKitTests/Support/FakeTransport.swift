import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import BitcoinKit

final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [String: (status: Int, data: Data)] = [:]
    private var _requests: [URLRequest] = []
    /// When set, every send throws this error.
    var failure: Error?

    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return _requests }

    func stub(_ path: String, status: Int = 200, data: Data) {
        lock.lock(); defer { lock.unlock() }
        routes[path] = (status, data)
    }

    func stub(_ path: String, fixture: String) throws {
        stub(path, data: try Fixture.data(fixture))
    }

    /// Stubs all six snapshot endpoints with recorded fixtures.
    func stubAllFixtures() throws {
        try stub("/api/v1/prices", fixture: "prices")
        try stub("/api/v1/historical-price", fixture: "historical-price")
        try stub("/api/v1/blocks", fixture: "blocks")
        try stub("/api/v1/fees/precise", fixture: "fees-precise")
        try stub("/api/mempool", fixture: "mempool")
        try stub("/api/v1/difficulty-adjustment", fixture: "difficulty-adjustment")
    }

    private func record(_ request: URLRequest) -> (status: Int, data: Data)? {
        lock.lock(); defer { lock.unlock() }
        _requests.append(request)
        return routes[request.url?.path ?? ""]
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let route = record(request)
        if let failure { throw failure }
        let (status, data) = route ?? (404, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (data, response)
    }
}

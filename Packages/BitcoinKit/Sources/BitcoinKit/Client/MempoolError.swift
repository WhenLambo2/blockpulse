public enum MempoolError: Error, Equatable, Sendable {
    case unauthorized
    case rateLimited
    case http(Int)
    case network(String)
    case decoding(String)

    /// The server doesn't know it (404), or says the input is malformed (400).
    public var isNotFound: Bool { self == .http(404) || self == .http(400) }

    public var userMessage: String {
        switch self {
        case .unauthorized: "Access denied (HTTP 401/403)"
        case .rateLimited: "Rate limited (HTTP 429)"
        case .http(let code): "Server error (HTTP \(code))"
        case .network(let message): "Network error: \(message)"
        case .decoding: "Unexpected response from server"
        }
    }
}

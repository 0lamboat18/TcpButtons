import Foundation
import Network

enum TCPError: LocalizedError {
    case emptyHost
    case invalidPort
    case invalidMessage
    case timedOut(TimeInterval)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .emptyHost: return "No host set. Open settings to add one."
        case .invalidPort: return "Port must be between 1 and 65535."
        case .invalidMessage: return "Message is empty or not valid UTF-8."
        case .timedOut(let seconds): return "No response after \(Int(seconds))s."
        case .network(let description): return description
        }
    }
}

enum TCPClient {

    private static let queue = DispatchQueue(label: "app.tcpbuttons.network")

    static func send(
        _ message: String,
        to host: String,
        port: UInt16,
        timeout: TimeInterval = 5,
        completion: @escaping (Result<TimeInterval, TCPError>) -> Void
    ) {
        guard let payload = message.data(using: .utf8), !payload.isEmpty else {
            DispatchQueue.main.async { completion(.failure(.invalidMessage)) }
            return
        }
        open(host, port, payload, timeout, completion)
    }

    static func ping(
        to host: String,
        port: UInt16,
        timeout: TimeInterval = 5,
        completion: @escaping (Result<TimeInterval, TCPError>) -> Void
    ) {
        open(host, port, nil, timeout, completion)
    }

    private static func open(
        _ host: String,
        _ port: UInt16,
        _ payload: Data?,
        _ timeout: TimeInterval,
        _ completion: @escaping (Result<TimeInterval, TCPError>) -> Void
    ) {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !host.isEmpty else {
            DispatchQueue.main.async { completion(.failure(.emptyHost)) }
            return
        }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            DispatchQueue.main.async { completion(.failure(.invalidPort)) }
            return
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        let start = Date()
        let once = OnceGuard()

        func finish(_ result: Result<TimeInterval, TCPError>) {
            once.run {
                connection.stateUpdateHandler = nil
                connection.cancel()
                DispatchQueue.main.async { completion(result) }
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let latency = Date().timeIntervalSince(start)
                guard let payload else {
                    finish(.success(latency))
                    return
                }
                connection.send(content: payload, completion: .contentProcessed { error in
                    if let error {
                        finish(.failure(.network(error.localizedDescription)))
                    } else {
                        finish(.success(latency))
                    }
                })
            case .failed(let error):
                finish(.failure(.network(error.localizedDescription)))
            case .cancelled:
                finish(.failure(.network("Connection closed.")))
            case .setup, .preparing, .waiting:
                break
            @unknown default:
                break
            }
        }

        queue.asyncAfter(deadline: .now() + timeout) { finish(.failure(.timedOut(timeout))) }
        connection.start(queue: queue)
    }

    private final class OnceGuard {
        private var hasRun = false

        func run(_ block: () -> Void) {
            guard !hasRun else { return }
            hasRun = true
            block()
        }
    }
}

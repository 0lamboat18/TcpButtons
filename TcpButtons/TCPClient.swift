import Foundation
import Network

/// Terminaison ajoutée à la fin de chaque message envoyé.
enum LineEnding: String, CaseIterable, Codable, Identifiable {
    case none
    case lf
    case crlf

    var id: String { rawValue }

    var suffix: String {
        switch self {
        case .none: return ""
        case .lf:   return "\n"
        case .crlf: return "\r\n"
        }
    }

    var label: String {
        switch self {
        case .none: return "Aucune"
        case .lf:   return #"\n"#
        case .crlf: return #"\r\n"#
        }
    }
}

enum TCPError: LocalizedError {
    case emptyHost
    case invalidPort
    case encodingFailed
    case timedOut(TimeInterval)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .emptyHost:
            return "Renseigne une adresse dans les paramètres."
        case .invalidPort:
            return "Le port doit être compris entre 1 et 65535."
        case .encodingFailed:
            return "Ce message ne peut pas être encodé en UTF-8."
        case .timedOut(let seconds):
            return "Aucune réponse après \(Int(seconds)) s."
        case .network(let description):
            return description
        }
    }
}

/// Client TCP « one-shot » : ouvre une connexion, envoie le message, referme.
///
/// Chaque appel invoque `completion` exactement une fois, sur la file principale.
enum TCPClient {

    private static let queue = DispatchQueue(label: "app.tcpbuttons.network")

    /// Ouvre une connexion et envoie `message`.
    /// - Returns: via `completion`, la latence de connexion en secondes.
    static func send(
        _ message: String,
        to host: String,
        port: UInt16,
        lineEnding: LineEnding = .lf,
        timeout: TimeInterval = 5,
        completion: @escaping (Result<TimeInterval, TCPError>) -> Void
    ) {
        guard let payload = (message + lineEnding.suffix).data(using: .utf8) else {
            DispatchQueue.main.async { completion(.failure(.encodingFailed)) }
            return
        }
        connect(to: host, port: port, sending: payload, timeout: timeout, completion: completion)
    }

    /// Ouvre une connexion sans rien envoyer, pour vérifier que l'hôte répond.
    static func ping(
        to host: String,
        port: UInt16,
        timeout: TimeInterval = 5,
        completion: @escaping (Result<TimeInterval, TCPError>) -> Void
    ) {
        connect(to: host, port: port, sending: nil, timeout: timeout, completion: completion)
    }

    // MARK: - Implémentation

    private static func connect(
        to host: String,
        port: UInt16,
        sending payload: Data?,
        timeout: TimeInterval,
        completion: @escaping (Result<TimeInterval, TCPError>) -> Void
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

        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: endpointPort,
            using: .tcp
        )
        let start = Date()
        let once = OnceGuard()

        // Toutes les écritures de `once` ont lieu sur `queue` : le handler de
        // NWConnection y est déjà confiné, et le timeout y est planifié.
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
                finish(.failure(.network("Connexion interrompue.")))

            case .setup, .preparing, .waiting:
                // `.waiting` n'est pas terminal : la connexion peut encore
                // aboutir. On laisse le timeout trancher.
                break

            @unknown default:
                break
            }
        }

        queue.asyncAfter(deadline: .now() + timeout) {
            finish(.failure(.timedOut(timeout)))
        }

        connection.start(queue: queue)
    }

    /// Garantit qu'un bloc ne s'exécute qu'une fois. À n'utiliser que depuis `queue`.
    private final class OnceGuard {
        private var hasRun = false

        func run(_ block: () -> Void) {
            guard !hasRun else { return }
            hasRun = true
            block()
        }
    }
}

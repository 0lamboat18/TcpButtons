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

    /// Toutes les opérations réseau et tout l'état partagé vivent sur cette file.
    private static let queue = DispatchQueue(label: "app.tcpbuttons.network", qos: .userInteractive)

    /// Connexion persistante utilisée par le mode rapide. Accès uniquement depuis `queue`.
    private static var session: Session?

    // MARK: - Paramètres TCP faible latence

    private static func makeParameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true               // pas d'algorithme de Nagle : le message part tout de suite
        tcp.enableKeepalive = true       // garde la connexion vivante et détecte une coupure
        tcp.keepaliveIdle = 10
        tcp.keepaliveInterval = 5
        tcp.keepaliveCount = 3
        tcp.connectionTimeout = 5

        let params = NWParameters(tls: nil, tcp: tcp)
        params.serviceClass = .interactiveVoice   // file Wi-Fi/cellulaire prioritaire (faible latence)
        params.preferNoProxies = true
        return params
    }

    // MARK: - Mode rapide : connexion persistante

    /// Ouvre (ou garde ouverte) la connexion vers `host:port` avant le premier appui.
    static func warmUp(host: String, port: UInt16) {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, let endpointPort = NWEndpoint.Port(rawValue: port) else { return }
        queue.async { _ = ensureSession(host: host, port: endpointPort) }
    }

    /// Ferme la connexion persistante (app en arrière-plan, changement de destination…).
    static func close() {
        queue.async {
            session?.close()
            session = nil
        }
    }

    /// Envoie sur la connexion persistante. Si elle est tombée, une nouvelle est ouverte
    /// et le message est renvoyé une fois. Renvoie le temps écoulé jusqu'à l'écriture.
    static func sendFast(
        _ message: String,
        to host: String,
        port: UInt16,
        completion: @escaping (Result<TimeInterval, TCPError>) -> Void
    ) {
        let t0 = DispatchTime.now().uptimeNanoseconds
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let payload = message.data(using: .utf8), !payload.isEmpty else {
            DispatchQueue.main.async { completion(.failure(.invalidMessage)) }
            return
        }
        guard !host.isEmpty else {
            DispatchQueue.main.async { completion(.failure(.emptyHost)) }
            return
        }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            DispatchQueue.main.async { completion(.failure(.invalidPort)) }
            return
        }

        queue.async {
            transmit(payload, host: host, port: endpointPort, retriesLeft: 1, t0: t0, completion: completion)
        }
    }

    private static func transmit(
        _ payload: Data,
        host: String,
        port: NWEndpoint.Port,
        retriesLeft: Int,
        t0: UInt64,
        completion: @escaping (Result<TimeInterval, TCPError>) -> Void
    ) {
        let s = ensureSession(host: host, port: port)
        // NWConnection met l'envoi en file d'attente même si la connexion n'est pas encore prête :
        // le message part dès que le TCP est établi, sans attendre notre code.
        s.connection.send(content: payload, completion: .contentProcessed { error in
            if let error {
                s.close()
                if retriesLeft > 0 {
                    queue.async {
                        transmit(payload, host: host, port: port, retriesLeft: retriesLeft - 1,
                                 t0: t0, completion: completion)
                    }
                } else {
                    DispatchQueue.main.async { completion(.failure(.network(error.localizedDescription))) }
                }
            } else {
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000_000
                DispatchQueue.main.async { completion(.success(elapsed)) }
            }
        })
    }

    private static func ensureSession(host: String, port: NWEndpoint.Port) -> Session {
        if let s = session, !s.isDead, s.host == host, s.port == port { return s }
        session?.close()
        let s = Session(host: host, port: port, queue: queue) { dead in
            if session === dead { session = nil }
        }
        session = s
        return s
    }

    private final class Session {
        let host: String
        let port: NWEndpoint.Port
        let connection: NWConnection
        private(set) var isDead = false

        init(host: String, port: NWEndpoint.Port, queue: DispatchQueue, onDead: @escaping (Session) -> Void) {
            self.host = host
            self.port = port
            connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: TCPClient.makeParameters())

            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .failed, .cancelled:
                    self.isDead = true
                    onDead(self)
                case .waiting:
                    // Pas de réseau utilisable : mieux vaut repartir à neuf au prochain appui.
                    self.close()
                default:
                    break
                }
            }
            connection.viabilityUpdateHandler = { [weak self] viable in
                if !viable { self?.close() }
            }
            connection.start(queue: queue)
        }

        func close() {
            isDead = true
            connection.cancel()
        }
    }

    // MARK: - Mode classique : une connexion par message

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

        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: makeParameters())
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

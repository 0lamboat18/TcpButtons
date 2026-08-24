import Foundation
import Network

final class EchoServer: ObservableObject {

    @Published private(set) var isRunning = false
    @Published private(set) var port: UInt16 = 9000
    @Published private(set) var lastError: String?

    var onReceive: ((String) -> Void)?

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "app.tcpbuttons.echo")

    func start(port requested: UInt16 = 9000) {
        stop()

        guard let endpointPort = NWEndpoint.Port(rawValue: requested) else {
            publish { self.lastError = "Port must be between 1 and 65535." }
            return
        }

        do {
            let listener = try NWListener(using: .tcp, on: endpointPort)

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.publish {
                        self.isRunning = true
                        self.port = requested
                        self.lastError = nil
                    }
                case .failed(let error):
                    self.publish {
                        self.isRunning = false
                        self.lastError = error.localizedDescription
                    }
                    self.stop()
                case .cancelled:
                    self.publish { self.isRunning = false }
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                self.connections.append(connection)
                connection.start(queue: self.queue)
                self.receive(on: connection)
            }

            self.listener = listener
            listener.start(queue: queue)

        } catch {
            publish {
                self.isRunning = false
                self.lastError = error.localizedDescription
            }
        }
    }

    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil

        connections.forEach { $0.cancel() }
        connections.removeAll()

        publish { self.isRunning = false }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                connection.send(content: data, completion: .idempotent)
                let text = String(decoding: data, as: UTF8.self)
                self.publish { self.onReceive?(text) }
            }

            if isComplete || error != nil {
                connection.cancel()
                self.connections.removeAll { $0 === connection }
            } else {
                self.receive(on: connection)
            }
        }
    }

    private func publish(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}

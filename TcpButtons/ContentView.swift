import SwiftUI
import Network

class TCPManager: ObservableObject {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "tcp", qos: .userInteractive)
    @Published var status: String = "Connexion..."
    @Published var connected: Bool = false

    let host: String
    let port: UInt16 = 9000

    init(host: String) {
        self.host = host
        connect()
    }

    func connect() {
        connected = false
        status = "Connexion..."
        connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.connected = true
                    self?.status = "Connecté"
                case .failed(_):
                    self?.connected = false
                    self?.status = "Déconnecté — nouvelle tentative..."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self?.connect()
                    }
                default: break
                }
            }
        }
        connection?.start(queue: queue)
    }

    func send(_ message: String) {
        guard connected, let data = (message + "\n").data(using: .utf8) else { return }
        connection?.send(content: data, completion: .contentProcessed { [weak self] error in
            DispatchQueue.main.async {
                if error != nil {
                    self?.status = "Erreur — reconnexion..."
                    self?.connect()
                } else {
                    self?.status = "\"\(message)\" envoyé"
                }
            }
        })
    }
}

struct ContentView: View {
    @StateObject private var tcp = TCPManager(host: "192.168.1.100")

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(tcp.connected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(tcp.status)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 48)

                VStack(spacing: 20) {
                    Button { tcp.send("dom") } label: {
                        Text("DOM")
                            .font(.system(size: 32, weight: .semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(tcp.connected ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(20)
                    }
                    .disabled(!tcp.connected)

                    Button { tcp.send("ext") } label: {
                        Text("EXT")
                            .font(.system(size: 32, weight: .semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(tcp.connected ? Color.green : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(20)
                    }
                    .disabled(!tcp.connected)
                }
                .frame(maxHeight: 400)
            }
            .padding(24)
        }
    }
}

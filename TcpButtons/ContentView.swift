import SwiftUI
import Network

class TCPManager: ObservableObject {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "tcp", qos: .userInteractive)
    @Published var status: String = "Connexion..."
    @Published var connected: Bool = false
    var host: String
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

    func updateHost(_ newHost: String) {
        connection?.cancel()
        host = newHost
        connect()
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

struct TCPButton: View {
    let label: String
    let color: Color
    let action: () -> Void
    let disabled: Bool

    @State private var pressed = false

    var body: some View {
        Button {
            action()
        } label: {
            Text(label)
                .font(.system(size: 32, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(disabled ? Color.gray : (pressed ? color.opacity(0.6) : color))
                .foregroundColor(.white)
                .cornerRadius(20)
                .scaleEffect(pressed ? 0.96 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: pressed)
        }
        .disabled(disabled)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        pressed = false
                    }
                }
        )
    }
}

struct ContentView: View {
    @StateObject private var tcp = TCPManager(host: UserDefaults.standard.string(forKey: "savedHost") ?? "192.168.1.100")
    @State private var ipInput: String = UserDefaults.standard.string(forKey: "savedHost") ?? "192.168.1.100"
    @State private var showIPField: Bool = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 0) {

                // Status + bouton réglages
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(tcp.connected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(tcp.status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        withAnimation { showIPField.toggle() }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 12)

                // Champ IP
                if showIPField {
                    HStack(spacing: 8) {
                        TextField("Adresse IP", text: $ipInput)
                            .keyboardType(.numbersAndPunctuation)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        Button("OK") {
                            let trimmed = ipInput.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            UserDefaults.standard.set(trimmed, forKey: "savedHost")
                            tcp.updateHost(trimmed)
                            withAnimation { showIPField = false }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.bottom, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Boutons
                VStack(spacing: 20) {
                    TCPButton(label: "DOM", color: .blue, action: { tcp.send("dom") }, disabled: !tcp.connected)
                    TCPButton(label: "EXT", color: .green, action: { tcp.send("ext") }, disabled: !tcp.connected)
                }
                .frame(maxHeight: 400)
                .padding(.top, 24)
            }
            .padding(24)
        }
    }
}

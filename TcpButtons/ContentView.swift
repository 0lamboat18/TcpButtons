import SwiftUI
import Network

class TCPManager: ObservableObject {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "tcp", qos: .userInteractive)
    @Published var status: String = "Démarrage..."
    @Published var connected: Bool = false
    @Published var logs: [String] = []
    var host: String
    let port: UInt16 = 9000

    init(host: String) {
        self.host = host
        addLog("Init avec host: \(host)")
        connect()
    }

    func addLog(_ msg: String) {
        DispatchQueue.main.async {
            let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            self.logs.insert("[\(time)] \(msg)", at: 0)
            if self.logs.count > 20 { self.logs.removeLast() }
        }
    }

    func connect() {
        addLog("Tentative connexion → \(host):\(port)")
        connected = false
        status = "Connexion à \(host)..."

        let endpoint = NWEndpoint.Host(host)
        guard let portEndpoint = NWEndpoint.Port(rawValue: port) else {
            addLog("❌ Port invalide")
            return
        }

        connection = NWConnection(host: endpoint, port: portEndpoint, using: .tcp)

        connection?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .setup:
                self.addLog("State: setup")
            case .preparing:
                self.addLog("State: préparation...")
            case .ready:
                self.addLog("✅ Connecté !")
                DispatchQueue.main.async {
                    self.connected = true
                    self.status = "Connecté à \(self.host)"
                }
            case .failed(let error):
                self.addLog("❌ Échec: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.connected = false
                    self.status = "Erreur: \(error.localizedDescription)"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.connect()
                }
            case .waiting(let reason):
                self.addLog("⏳ En attente: \(reason)")
                DispatchQueue.main.async {
                    self.connected = false
                    self.status = "En attente: \(reason)"
                }
            case .cancelled:
                self.addLog("🚫 Annulé")
            @unknown default:
                self.addLog("State inconnu")
            }
        }

        connection?.start(queue: queue)
    }

    func updateHost(_ newHost: String) {
        addLog("Changement IP → \(newHost)")
        connection?.cancel()
        host = newHost
        connect()
    }

    func send(_ message: String) {
        guard connected, let data = (message + "\n").data(using: .utf8) else {
            addLog("⚠️ Envoi impossible (non connecté)")
            return
        }
        addLog("📤 Envoi: \(message)")
        connection?.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.addLog("❌ Erreur envoi: \(error.localizedDescription)")
                self?.connect()
            } else {
                self?.addLog("✅ Envoyé: \(message)")
                DispatchQueue.main.async { self?.status = "\"\(message)\" envoyé" }
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
        Button { action() } label: {
            Text(label)
                .font(.system(size: 32, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .background(disabled ? Color.gray : (pressed ? color.opacity(0.6) : color))
                .foregroundColor(.white)
                .cornerRadius(20)
                .scaleEffect(pressed ? 0.96 : 1.0)
                .animation(.easeInOut(duration: 0.05), value: pressed)
        }
        .disabled(disabled)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { pressed = false }
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
            VStack(spacing: 12) {

                // Status
                HStack {
                    Circle()
                        .fill(tcp.connected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(tcp.status)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        withAnimation { showIPField.toggle() }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.secondary)
                    }
                }

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
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Boutons
                TCPButton(label: "DOM", color: .blue, action: { tcp.send("dom") }, disabled: !tcp.connected)
                TCPButton(label: "EXT", color: .green, action: { tcp.send("ext") }, disabled: !tcp.connected)

                // Logs
                VStack(alignment: .leading, spacing: 0) {
                    Text("Logs")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(tcp.logs, id: \.self) { log in
                                Text(log)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .frame(maxHeight: 250)
            }
            .padding(16)
        }
    }
}

import SwiftUI
import Network

func sendTCP(message: String, host: String, port: UInt16 = 9000, completion: @escaping (String) -> Void) {
    let queue = DispatchQueue(label: "tcp.send", qos: .userInteractive)
    let connection = NWConnection(
        host: NWEndpoint.Host(host),
        port: NWEndpoint.Port(rawValue: port)!,
        using: .tcp
    )

    connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
            guard let data = (message + "\n").data(using: .utf8) else {
                completion("❌ Encodage message impossible")
                connection.cancel()
                return
            }
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    completion("❌ Erreur envoi: \(error.localizedDescription)")
                } else {
                    completion("✅ \"\(message)\" envoyé à \(host):\(port)")
                }
                connection.cancel()
            })
        case .failed(let error):
            completion("❌ Connexion impossible: \(error.localizedDescription)")
            connection.cancel()
        case .waiting(let reason):
            completion("⏳ En attente: \(reason)")
            connection.cancel()
        default:
            break
        }
    }
    connection.start(queue: queue)
}

func pingTCP(host: String, port: UInt16 = 9000, completion: @escaping (String) -> Void) {
    let queue = DispatchQueue(label: "tcp.ping", qos: .userInteractive)
    let connection = NWConnection(
        host: NWEndpoint.Host(host),
        port: NWEndpoint.Port(rawValue: port)!,
        using: .tcp
    )
    let start = Date()

    connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            completion("🟢 Connecté en \(ms)ms")
            connection.cancel()
        case .failed(let error):
            completion("🔴 Échec: \(error.localizedDescription)")
            connection.cancel()
        case .waiting(let reason):
            completion("🔴 Injoignable: \(reason)")
            connection.cancel()
        default:
            break
        }
    }
    connection.start(queue: queue)
}

struct TCPButton: View {
    let label: String
    let color: Color
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button { action() } label: {
            Text(label)
                .font(.system(size: 32, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(pressed ? color.opacity(0.6) : color)
                .foregroundColor(.white)
                .cornerRadius(20)
                .scaleEffect(pressed ? 0.96 : 1.0)
                .animation(.easeInOut(duration: 0.08), value: pressed)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { pressed = false }
                }
        )
    }
}

struct ContentView: View {
    @State private var host: String = UserDefaults.standard.string(forKey: "savedHost") ?? "192.168.1.100"
    @State private var port: String = UserDefaults.standard.string(forKey: "savedPort") ?? "9000"
    @State private var ipInput: String = UserDefaults.standard.string(forKey: "savedHost") ?? "192.168.1.100"
    @State private var portInput: String = UserDefaults.standard.string(forKey: "savedPort") ?? "9000"
    @State private var showSettings: Bool = false
    @State private var showLogs: Bool = true
    @State private var lastStatus: String = "Prêt"
    @State private var logs: [String] = []
    @State private var isTesting: Bool = false

    func send(_ message: String) {
        let p = UInt16(port) ?? 9000
        addLog("📤 Envoi '\(message)' → \(host):\(p)")
        sendTCP(message: message, host: host, port: p) { result in
            DispatchQueue.main.async {
                lastStatus = result
                addLog(result)
            }
        }
    }

    func addLog(_ msg: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.insert("[\(time)] \(msg)", at: 0)
        if logs.count > 20 { logs.removeLast() }
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 12) {

                // Status + réglages + toggle logs — toujours visible
                HStack {
                    Text(lastStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showLogs.toggle() }
                    } label: {
                        Image(systemName: showLogs ? "list.bullet" : "list.bullet.slash")
                            .foregroundColor(.secondary)
                    }
                    .padding(.trailing, 10)
                    Button {
                        withAnimation { showSettings.toggle() }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.secondary)
                    }
                }

                // Champs IP + Port
                if showSettings {
                    HStack(spacing: 8) {
                        TextField("Adresse IP / host", text: $ipInput)
                            .keyboardType(.numbersAndPunctuation)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        TextField("Port", text: $portInput)
                            .keyboardType(.numberPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 70)
                        Button("OK") {
                            host = ipInput.trimmingCharacters(in: .whitespaces)
                            port = portInput.trimmingCharacters(in: .whitespaces)
                            UserDefaults.standard.set(host, forKey: "savedHost")
                            UserDefaults.standard.set(port, forKey: "savedPort")
                            addLog("⚙️ Config: \(host):\(port)")
                            withAnimation { showSettings = false }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Bouton test connexion
                Button {
                    isTesting = true
                    lastStatus = "Test en cours..."
                    addLog("🔌 Test connexion → \(host):\(port)")
                    let p = UInt16(port) ?? 9000
                    pingTCP(host: host, port: p) { result in
                        DispatchQueue.main.async {
                            lastStatus = result
                            addLog(result)
                            isTesting = false
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isTesting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(isTesting ? "Test..." : "Tester la connexion")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(isTesting ? Color.orange.opacity(0.6) : Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isTesting)

                // Boutons DOM / EXT — s'étendent si logs cachés
                VStack(spacing: 12) {
                    TCPButton(label: "DOM", color: .blue, action: { send("dom") })
                    TCPButton(label: "EXT", color: .green, action: { send("ext") })
                }
                .frame(maxHeight: showLogs ? 172 : .infinity)
                .animation(.easeInOut(duration: 0.2), value: showLogs)

                // Logs
                if showLogs {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Logs")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.top, 6)
                        Divider()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(logs, id: \.self) { log in
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
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(16)
        }
    }
}

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

// ── Couleurs disponibles ───────────────────────────────────────────────────
struct NamedColor: Identifiable, Equatable {
    let id: String
    let color: Color
}

let availableColors: [NamedColor] = [
    NamedColor(id: "Bleu",   color: .blue),
    NamedColor(id: "Vert",   color: .green),
    NamedColor(id: "Rouge",  color: .red),
    NamedColor(id: "Orange", color: .orange),
    NamedColor(id: "Violet", color: .purple),
    NamedColor(id: "Rose",   color: .pink),
    NamedColor(id: "Cyan",   color: .cyan),
    NamedColor(id: "Jaune",  color: .yellow),
    NamedColor(id: "Gris",   color: .gray),
]

func colorFromId(_ id: String) -> Color {
    availableColors.first { $0.id == id }?.color ?? .blue
}

// ── Sélecteur de couleur ───────────────────────────────────────────────────
struct ButtonColorPicker: View {
    let label: String
    @Binding var selectedId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableColors) { nc in
                        Circle()
                            .fill(nc.color)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary, lineWidth: selectedId == nc.id ? 3 : 0)
                                    .padding(2)
                            )
                            .onTapGesture { selectedId = nc.id }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

// ── Bouton principal ───────────────────────────────────────────────────────
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

// ── Vue principale ─────────────────────────────────────────────────────────
struct ContentView: View {
    @State private var host: String = UserDefaults.standard.string(forKey: "savedHost") ?? "192.168.1.100"
    @State private var port: String = UserDefaults.standard.string(forKey: "savedPort") ?? "9000"
    @State private var ipInput: String = UserDefaults.standard.string(forKey: "savedHost") ?? "192.168.1.100"
    @State private var portInput: String = UserDefaults.standard.string(forKey: "savedPort") ?? "9000"

    @State private var btn1Label: String = UserDefaults.standard.string(forKey: "btn1Label") ?? "DOM"
    @State private var btn2Label: String = UserDefaults.standard.string(forKey: "btn2Label") ?? "EXT"
    @State private var btn1ColorId: String = UserDefaults.standard.string(forKey: "btn1Color") ?? "Bleu"
    @State private var btn2ColorId: String = UserDefaults.standard.string(forKey: "btn2Color") ?? "Vert"
    @State private var btn1LabelInput: String = UserDefaults.standard.string(forKey: "btn1Label") ?? "DOM"
    @State private var btn2LabelInput: String = UserDefaults.standard.string(forKey: "btn2Label") ?? "EXT"
    @State private var btn1ColorInput: String = UserDefaults.standard.string(forKey: "btn1Color") ?? "Bleu"
    @State private var btn2ColorInput: String = UserDefaults.standard.string(forKey: "btn2Color") ?? "Vert"

    @State private var showSettings: Bool = false
    @State private var showLogs: Bool = true
    @State private var safetyMode: Bool = true  // ON par défaut à chaque lancement
    @State private var lastStatus: String = "Prêt"
    @State private var logs: [String] = []
    @State private var isTesting: Bool = false

    func send(_ message: String) {
        let p = UInt16(port) ?? 9000
        let actualMessage = safetyMode ? "" : message
        addLog("📤 Envoi '\(actualMessage)' → \(host):\(p)")
        sendTCP(message: actualMessage, host: host, port: p) { result in
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

    func saveSettings() {
        host = ipInput.trimmingCharacters(in: .whitespaces)
        port = portInput.trimmingCharacters(in: .whitespaces)
        btn1Label = btn1LabelInput.trimmingCharacters(in: .whitespaces).isEmpty ? "BTN1" : btn1LabelInput.trimmingCharacters(in: .whitespaces)
        btn2Label = btn2LabelInput.trimmingCharacters(in: .whitespaces).isEmpty ? "BTN2" : btn2LabelInput.trimmingCharacters(in: .whitespaces)
        btn1ColorId = btn1ColorInput
        btn2ColorId = btn2ColorInput
        UserDefaults.standard.set(host,        forKey: "savedHost")
        UserDefaults.standard.set(port,        forKey: "savedPort")
        UserDefaults.standard.set(btn1Label,   forKey: "btn1Label")
        UserDefaults.standard.set(btn2Label,   forKey: "btn2Label")
        UserDefaults.standard.set(btn1ColorId, forKey: "btn1Color")
        UserDefaults.standard.set(btn2ColorId, forKey: "btn2Color")
        addLog("⚙️ Config sauvegardée")
        withAnimation { showSettings = false }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                (safetyMode ? Color.white : Color.black)
                    .ignoresSafeArea()
                VStack(spacing: 12) {

                    // ── Barre du haut ──────────────────────────────────────
                    HStack(spacing: 12) {
                        Text(lastStatus)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            if !showSettings {
                                ipInput      = host
                                portInput    = port
                                btn1LabelInput = btn1Label
                                btn2LabelInput = btn2Label
                                btn1ColorInput = btn1ColorId
                                btn2ColorInput = btn2ColorId
                            }
                            withAnimation { showSettings.toggle() }
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)

                    // ── Paramètres ────────────────────────────────────────
                    if showSettings {
                        VStack(alignment: .leading, spacing: 12) {

                            // IP / Port
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
                            }

                            Divider()

                            // Bouton 1
                            Text("Bouton 1")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                TextField("Texte", text: $btn1LabelInput)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .frame(width: 90)
                                Text(btn1LabelInput.isEmpty ? "BTN1" : btn1LabelInput)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(colorFromId(btn1ColorInput))
                                    .cornerRadius(8)
                            }
                            ButtonColorPicker(label: "Couleur", selectedId: $btn1ColorInput)

                            Divider()

                            // Bouton 2
                            Text("Bouton 2")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                TextField("Texte", text: $btn2LabelInput)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .frame(width: 90)
                                Text(btn2LabelInput.isEmpty ? "BTN2" : btn2LabelInput)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(colorFromId(btn2ColorInput))
                                    .cornerRadius(8)
                            }
                            ButtonColorPicker(label: "Couleur", selectedId: $btn2ColorInput)

                            Divider()

                            // Sécurité toggle
                            Toggle(isOn: $safetyMode) {
                                Text("Sécurité")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 4)

                            // Logs toggle
                            Toggle(isOn: $showLogs) {
                                Text("Afficher les logs")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 4)

                            // Bouton enregistrer
                            Button("Enregistrer") { saveSettings() }
                                .buttonStyle(.borderedProminent)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // ── Bouton test connexion ─────────────────────────────
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

                    // ── Boutons principaux ────────────────────────────────
                    let logsHeight: CGFloat = showLogs ? 200 : 0
                    let fixedHeight: CGFloat = 44 + 44 + 12 * 5 + 30
                    let buttonsHeight = max(120, geo.size.height - fixedHeight - logsHeight - (showSettings ? 50 : 0))

                    VStack(spacing: 12) {
                        TCPButton(label: btn1Label, color: colorFromId(btn1ColorId), action: { send("pg_" + btn1Label + " /// " + "true" + " ; " + btn1Label) })
                        TCPButton(label: btn2Label, color: colorFromId(btn2ColorId), action: { send("pg_" + btn1Label + " /// " + "true" + " ; " + btn2Label) })
                    }
                    .frame(height: showLogs ? min(buttonsHeight, 280) : buttonsHeight)

                    // ── Logs ──────────────────────────────────────────────
                    if showLogs {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Logs")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.top, 6)
                            Divider()
                            ScrollView {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(Array(logs.enumerated()), id: \.offset) { _, log in
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
                        .frame(height: 200)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(16)
            }
        }
    }
}

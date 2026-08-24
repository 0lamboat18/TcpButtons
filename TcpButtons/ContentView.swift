import SwiftUI

struct ContentView: View {
    @StateObject private var settings = AppSettings()

    @State private var logs: [LogEntry] = []
    @State private var status: String = "Prêt"
    @State private var isTesting = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if settings.dryRun {
                    dryRunBanner
                }

                buttonStack

                testButton

                if settings.showLogs {
                    LogView(entries: logs)
                        .frame(height: 180)
                }
            }
            .padding(16)
            .navigationTitle(destinationLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Paramètres")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: settings)
            }
        }
    }

    // MARK: - Sous-vues

    private var destinationLabel: String {
        "\(settings.host):\(settings.port)"
    }

    private var dryRunBanner: some View {
        Label("Mode test — rien n'est envoyé", systemImage: "eye")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var buttonStack: some View {
        VStack(spacing: 12) {
            ForEach(settings.buttons) { button in
                SendButton(config: button) { send(button) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var testButton: some View {
        Button {
            testConnection()
        } label: {
            HStack(spacing: 8) {
                if isTesting {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                }
                Text(isTesting ? "Test en cours" : "Tester la connexion")
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.accentColor.opacity(isTesting ? 0.6 : 1))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isTesting)
    }

    // MARK: - Actions

    private func send(_ button: TCPButtonConfig) {
        guard !button.message.isEmpty else {
            status = "Message vide"
            log(.failure, "\(button.displayLabel) : aucun message défini dans les paramètres")
            return
        }

        guard !settings.dryRun else {
            log(.info, "Mode test — non envoyé : \(display(button.message))")
            status = "Mode test actif"
            return
        }

        log(.sent, "\(display(button.message)) → \(destinationLabel)")

        TCPClient.send(
            button.message,
            to: settings.host,
            port: settings.port
        ) { result in
            switch result {
            case .success:
                status = "Envoyé"
                log(.success, "\(button.displayLabel) envoyé")
            case .failure(let error):
                let message = error.localizedDescription
                status = message
                log(.failure, message)
            }
        }
    }

    private func testConnection() {
        isTesting = true
        status = "Connexion à \(destinationLabel)…"

        TCPClient.ping(to: settings.host, port: settings.port) { result in
            isTesting = false
            switch result {
            case .success(let latency):
                let ms = Int(latency * 1000)
                status = "Connecté en \(ms) ms"
                log(.success, "Connecté à \(destinationLabel) en \(ms) ms")
            case .failure(let error):
                let message = error.localizedDescription
                status = message
                log(.failure, message)
            }
        }
    }

    private func display(_ message: String) -> String {
        message.isEmpty ? "(message vide)" : message
    }

    private func log(_ kind: LogEntry.Kind, _ text: String) {
        logs.insert(LogEntry(kind: kind, text: text), at: 0)
        if logs.count > 50 { logs.removeLast() }
    }
}

// MARK: - Bouton d'envoi

private struct SendButton: View {
    let config: TCPButtonConfig
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(config.displayLabel)
                .font(.system(size: 32, weight: .semibold))
                .minimumScaleFactor(0.5)
                .lineLimit(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(.white)
                .background(config.color, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(PressEffectStyle())
        .accessibilityHint("Envoie « \(config.message) »")
    }
}

private struct PressEffectStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Journal

private struct LogView: View {
    let entries: [LogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Journal")
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            if entries.isEmpty {
                Text("Les envois apparaîtront ici.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(entries) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: entry.kind.symbol)
                                    .foregroundStyle(entry.kind.tint)
                                    .font(.system(size: 10))
                                Text(entry.timestamp)
                                    .foregroundStyle(.secondary)
                                Text(entry.text)
                                    .textSelection(.enabled)
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

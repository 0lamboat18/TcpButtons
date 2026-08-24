import SwiftUI

struct ContentView: View {
    @StateObject private var settings = AppSettings()

    @State private var log: [LogEntry] = []
    @State private var status = "Ready"
    @State private var isTesting = false
    @State private var showSettings = false

    private var destination: String {
        settings.host.isEmpty ? "No destination" : "\(settings.host):\(settings.port)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if settings.testMode {
                    Label("Test mode — nothing is sent", systemImage: "eye")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }

                VStack(spacing: 12) {
                    ForEach(settings.buttons) { button in
                        SendButton(config: button) { send(button) }
                    }
                }
                .frame(maxHeight: .infinity)

                testButton

                if settings.showLog {
                    LogView(entries: log).frame(height: 180)
                }
            }
            .padding(16)
            .navigationTitle(destination)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
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

    private var testButton: some View {
        Button(action: testConnection) {
            HStack(spacing: 8) {
                if isTesting {
                    ProgressView().tint(.white).scaleEffect(0.8)
                }
                Text(isTesting ? "Testing" : "Test connection")
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.accentColor.opacity(isTesting ? 0.6 : 1))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isTesting)
    }

    private func send(_ button: TCPButtonConfig) {
        guard !button.message.isEmpty else {
            status = "No message set"
            append(.failure, "\(button.displayLabel): no message set in settings")
            return
        }

        guard !settings.testMode else {
            status = "Test mode"
            append(.info, "Not sent: \(button.message)")
            return
        }

        append(.sent, "\(button.message) → \(destination)")

        TCPClient.send(button.message, to: settings.host, port: settings.port) { result in
            switch result {
            case .success:
                status = "Sent"
                append(.success, "\(button.displayLabel) sent")
            case .failure(let error):
                status = error.localizedDescription
                append(.failure, error.localizedDescription)
            }
        }
    }

    private func testConnection() {
        isTesting = true
        status = "Connecting to \(destination)"

        TCPClient.ping(to: settings.host, port: settings.port) { result in
            isTesting = false
            switch result {
            case .success(let latency):
                let ms = Int(latency * 1000)
                status = "Connected in \(ms) ms"
                append(.success, "Connected to \(destination) in \(ms) ms")
            case .failure(let error):
                status = error.localizedDescription
                append(.failure, error.localizedDescription)
            }
        }
    }

    private func append(_ kind: LogEntry.Kind, _ text: String) {
        log.insert(LogEntry(kind: kind, text: text), at: 0)
        if log.count > 50 { log.removeLast() }
    }
}

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
        .buttonStyle(PressEffect())
    }
}

private struct PressEffect: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct LogView: View {
    let entries: [LogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Log")
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            if entries.isEmpty {
                Text("Activity will appear here.")
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
                                Text(entry.timestamp).foregroundStyle(.secondary)
                                Text(entry.text).textSelection(.enabled)
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

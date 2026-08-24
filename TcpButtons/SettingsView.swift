import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var echo: EchoServer
    @Environment(\.dismiss) private var dismiss

    @State private var portText = ""

    var body: some View {
        NavigationStack {
            Form {
                destinationSection
                echoSection
                ForEach($settings.buttons) { $button in
                    buttonSection($button)
                }
                behaviourSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commitPort()
                        dismiss()
                    }
                }
            }
            .onAppear { portText = String(settings.port) }
        }
    }

    private var destinationSection: some View {
        Section {
            LabeledContent("Host") {
                TextField("192.168.1.100", text: $settings.host)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Port") {
                TextField("9000", text: $portText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .onSubmit(commitPort)
            }
        } header: {
            Text("Destination")
        } footer: {
            Text("IP address or hostname of the server receiving the messages.")
        }
    }

    private var echoSection: some View {
        Section {
            Toggle("Local echo server", isOn: Binding(
                get: { echo.isRunning },
                set: { running in
                    if running {
                        echo.start(port: 9000)
                    } else {
                        echo.stop()
                    }
                }
            ))

            if echo.isRunning {
                Button("Point app at echo server") {
                    settings.host = "127.0.0.1"
                    settings.port = echo.port
                    portText = String(echo.port)
                }
            }

            if let error = echo.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Echo server")
        } footer: {
            Text("Starts a TCP server on 127.0.0.1 that echoes back whatever it receives. Use it to try the app without any external hardware.")
        }
    }

    private func buttonSection(_ button: Binding<TCPButtonConfig>) -> some View {
        Section {
            LabeledContent("Title") {
                TextField("Button title", text: button.label)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Message")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Tap to type", text: button.message, axis: .vertical)
                    .lineLimit(1...4)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.tertiarySystemFill))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                            }
                    }
            }

            ColorRow(selectedId: button.colorId)
        } header: {
            Text(button.wrappedValue.displayLabel)
        } footer: {
            Text("Sent exactly as typed, UTF-8, with no added characters.")
        }
    }

    private var behaviourSection: some View {
        Section {
            Toggle("Show log", isOn: $settings.showLog)
            Toggle("Test mode", isOn: $settings.testMode)
        } footer: {
            Text("In test mode, buttons log the message without opening a connection.")
        }
    }

    private func commitPort() {
        if let value = UInt16(portText.filter(\.isNumber)), value > 0 {
            settings.port = value
        }
        portText = String(settings.port)
    }
}

private struct ColorRow: View {
    @Binding var selectedId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(Palette.all) { named in
                    Button { selectedId = named.id } label: {
                        Circle()
                            .fill(named.color)
                            .frame(width: 28, height: 28)
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.primary, lineWidth: selectedId == named.id ? 3 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(named.id)
                    .accessibilityAddTraits(selectedId == named.id ? [.isSelected] : [])
                }
            }
        }
        .padding(.vertical, 4)
    }
}

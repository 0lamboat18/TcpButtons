import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var portText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                destinationSection

                ForEach($settings.buttons) { $button in
                    buttonSection(for: $button)
                }

                behaviourSection
            }
            .navigationTitle("Paramètres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") {
                        commitPort()
                        dismiss()
                    }
                }
            }
            .onAppear { portText = String(settings.port) }
        }
    }

    // MARK: - Sections

    private var destinationSection: some View {
        Section {
            LabeledContent("Adresse") {
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
                    .onSubmit { commitPort() }
            }
        } header: {
            Text("Destination")
        } footer: {
            Text("Adresse IP ou nom d'hôte du serveur qui reçoit les messages.")
        }
    }

    private func buttonSection(for button: Binding<TCPButtonConfig>) -> some View {
        Section {
            LabeledContent("Titre") {
                TextField("Titre affiché", text: button.label)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Message envoyé")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Touchez ici pour écrire", text: button.message, axis: .vertical)
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
        }
    }

    private var behaviourSection: some View {
        Section {
            Toggle("Afficher le journal", isOn: $settings.showLogs)
            Toggle("Mode test", isOn: $settings.dryRun)
        } footer: {
            Text("En mode test, les boutons affichent le message dans le journal sans rien envoyer.")
        }
    }

    // MARK: - Validation

    private func commitPort() {
        let digits = portText.filter(\.isNumber)
        if let value = UInt16(digits), value > 0 {
            settings.port = value
        }
        portText = String(settings.port)
    }
}

// MARK: - Sélecteur de couleur

private struct ColorRow: View {
    @Binding var selectedId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couleur")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(Palette.all) { named in
                    Button {
                        selectedId = named.id
                    } label: {
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

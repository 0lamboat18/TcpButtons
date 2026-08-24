import SwiftUI

// MARK: - Couleurs

struct NamedColor: Identifiable, Equatable {
    let id: String
    let color: Color
}

enum Palette {
    static let all: [NamedColor] = [
        NamedColor(id: "blue",   color: .blue),
        NamedColor(id: "green",  color: .green),
        NamedColor(id: "red",    color: .red),
        NamedColor(id: "orange", color: .orange),
        NamedColor(id: "purple", color: .purple),
        NamedColor(id: "pink",   color: .pink),
        NamedColor(id: "cyan",   color: .cyan),
        NamedColor(id: "yellow", color: .yellow),
        NamedColor(id: "gray",   color: .gray)
    ]

    static func color(_ id: String) -> Color {
        all.first { $0.id == id }?.color ?? .blue
    }
}

// MARK: - Bouton

/// Un bouton de l'écran principal : ce qu'on lit dessus, et ce qu'il envoie.
struct TCPButtonConfig: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var label: String
    var message: String
    var colorId: String

    var color: Color { Palette.color(colorId) }

    /// Libellé affiché, avec repli si l'utilisateur a tout effacé.
    var displayLabel: String {
        label.trimmingCharacters(in: .whitespaces).isEmpty ? "Sans nom" : label
    }
}

// MARK: - Réglages

/// Source de vérité unique de l'app, persistée dans `UserDefaults`.
@MainActor
final class AppSettings: ObservableObject {

    @Published var host: String                { didSet { save() } }
    @Published var port: UInt16                { didSet { save() } }
    @Published var buttons: [TCPButtonConfig]  { didSet { save() } }
    @Published var showLogs: Bool              { didSet { save() } }
    @Published var dryRun: Bool                { didSet { save() } }

    private let defaults: UserDefaults
    private var isLoading = false

    private enum Key {
        static let host = "host"
        static let port = "port"
        static let buttons = "buttons"
        static let showLogs = "showLogs"
        static let dryRun = "dryRun"
    }

    static let defaultButtons: [TCPButtonConfig] = [
        TCPButtonConfig(label: "Bouton 1", message: "", colorId: "blue"),
        TCPButtonConfig(label: "Bouton 2", message: "", colorId: "green")
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isLoading = true

        host = defaults.string(forKey: Key.host) ?? "192.168.1.100"

        let storedPort = defaults.integer(forKey: Key.port)
        port = (1...65535).contains(storedPort) ? UInt16(storedPort) : 9000

        if let data = defaults.data(forKey: Key.buttons),
           let decoded = try? JSONDecoder().decode([TCPButtonConfig].self, from: data),
           !decoded.isEmpty {
            buttons = decoded
        } else {
            buttons = Self.defaultButtons
        }

        showLogs = defaults.object(forKey: Key.showLogs) as? Bool ?? true
        dryRun = defaults.object(forKey: Key.dryRun) as? Bool ?? false

        isLoading = false
    }

    private func save() {
        guard !isLoading else { return }
        defaults.set(host, forKey: Key.host)
        defaults.set(Int(port), forKey: Key.port)
        defaults.set(showLogs, forKey: Key.showLogs)
        defaults.set(dryRun, forKey: Key.dryRun)
        if let data = try? JSONEncoder().encode(buttons) {
            defaults.set(data, forKey: Key.buttons)
        }
    }
}

// MARK: - Journal

struct LogEntry: Identifiable {
    enum Kind {
        case sent, success, failure, info

        var symbol: String {
            switch self {
            case .sent:    return "arrow.up.circle"
            case .success: return "checkmark.circle"
            case .failure: return "exclamationmark.triangle"
            case .info:    return "info.circle"
            }
        }

        var tint: Color {
            switch self {
            case .sent:    return .secondary
            case .success: return .green
            case .failure: return .red
            case .info:    return .secondary
            }
        }
    }

    let id = UUID()
    let date = Date()
    let kind: Kind
    let text: String

    var timestamp: String {
        LogEntry.formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}

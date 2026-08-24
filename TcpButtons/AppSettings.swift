import SwiftUI

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

struct TCPButtonConfig: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var label: String
    var message: String
    var colorId: String

    var color: Color { Palette.color(colorId) }

    var displayLabel: String {
        label.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : label
    }
}

@MainActor
final class AppSettings: ObservableObject {

    @Published var host: String               { didSet { save() } }
    @Published var port: UInt16               { didSet { save() } }
    @Published var buttons: [TCPButtonConfig] { didSet { save() } }
    @Published var showLog: Bool              { didSet { save() } }
    @Published var testMode: Bool             { didSet { save() } }

    static let defaultButtons: [TCPButtonConfig] = [
        TCPButtonConfig(label: "Button 1", message: "", colorId: "blue"),
        TCPButtonConfig(label: "Button 2", message: "", colorId: "green")
    ]

    private let defaults: UserDefaults
    private var isLoading = false

    private enum Key {
        static let host = "host"
        static let port = "port"
        static let buttons = "buttons"
        static let showLog = "showLog"
        static let testMode = "testMode"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isLoading = true

        host = defaults.string(forKey: Key.host) ?? ""

        let storedPort = defaults.integer(forKey: Key.port)
        port = (1...65535).contains(storedPort) ? UInt16(storedPort) : 9000

        if let data = defaults.data(forKey: Key.buttons),
           let decoded = try? JSONDecoder().decode([TCPButtonConfig].self, from: data),
           !decoded.isEmpty {
            buttons = decoded
        } else {
            buttons = Self.defaultButtons
        }

        showLog = defaults.object(forKey: Key.showLog) as? Bool ?? true
        testMode = defaults.object(forKey: Key.testMode) as? Bool ?? false

        isLoading = false
    }

    private func save() {
        guard !isLoading else { return }
        defaults.set(host, forKey: Key.host)
        defaults.set(Int(port), forKey: Key.port)
        defaults.set(showLog, forKey: Key.showLog)
        defaults.set(testMode, forKey: Key.testMode)
        if let data = try? JSONEncoder().encode(buttons) {
            defaults.set(data, forKey: Key.buttons)
        }
    }
}

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
            case .sent, .info: return .secondary
            case .success:     return .green
            case .failure:     return .red
            }
        }
    }

    let id = UUID()
    let date = Date()
    let kind: Kind
    let text: String

    var timestamp: String { LogEntry.formatter.string(from: date) }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}

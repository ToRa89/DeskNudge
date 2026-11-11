import DeskCore
import Foundation
import os

@MainActor
final class SettingsStore: ObservableObject {
    private static let key = "deskSettings"
    private let defaults: UserDefaults
    private let log = Logger(subsystem: "local.desknudge", category: "settings")

    @Published var settings: DeskSettings {
        didSet { save() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(DeskSettings.self, from: data) {
            settings = decoded
        } else {
            settings = DeskSettings()
        }
    }

    func centimetres(_ position: UInt16) -> String {
        let value = LinakCodec.centimetres(position: position, baseHeightCm: settings.baseHeightCm)
        return value.formatted(.number.precision(.fractionLength(1))) + " cm"
    }

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: Self.key)
        } catch {
            log.error("saving settings failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

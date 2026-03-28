import Foundation

actor SettingsStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let settingsURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.settingsURL = appSupport
            .appendingPathComponent("YunxuOllamaChat", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    func loadSettings() throws -> AppSettings {
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            return .default
        }

        let data = try Data(contentsOf: settingsURL)
        return try decoder.decode(AppSettings.self, from: data)
    }

    func saveSettings(_ settings: AppSettings) throws {
        let directory = settingsURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(settings)
        try data.write(to: settingsURL, options: .atomic)
    }
}

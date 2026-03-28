import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings = .default
    @Published var availableModels: [String] = []
    @Published var runningModels: [OllamaRunningModel] = []
    @Published var connectionStatus: OllamaConnectionStatus = .unknown
    @Published var errorMessage: String?

    private let store: SettingsStore
    private let ollamaClient: OllamaClient

    init(store: SettingsStore, ollamaClient: OllamaClient) {
        self.store = store
        self.ollamaClient = ollamaClient
    }

    func load() async {
        do {
            settings = try await store.loadSettings()
        } catch {
            errorMessage = "Failed to load settings: \(error.localizedDescription)"
        }
    }

    func save() async {
        do {
            try await store.saveSettings(settings)
        } catch {
            errorMessage = "Failed to save settings: \(error.localizedDescription)"
        }
    }

    func refreshModels() async {
        guard let baseURL = settings.baseURL else {
            connectionStatus = .disconnected("Invalid URL")
            errorMessage = "請確認 Ollama Base URL 格式是否正確。"
            return
        }

        connectionStatus = .checking
        errorMessage = nil

        do {
            async let tagsTask = ollamaClient.fetchTags(baseURL: baseURL)
            async let runningModelsTask = ollamaClient.fetchRunningModels(baseURL: baseURL)

            let tags = try await tagsTask
            let runningModels = (try? await runningModelsTask) ?? []
            availableModels = tags.map(\.name)
            self.runningModels = runningModels
            connectionStatus = .connected

            if !availableModels.isEmpty, !availableModels.contains(settings.selectedModel) {
                if availableModels.contains(AppSettings.default.selectedModel) {
                    settings.selectedModel = AppSettings.default.selectedModel
                } else if let firstModel = availableModels.first {
                    settings.selectedModel = firstModel
                }
                await save()
            }
        } catch {
            availableModels = []
            runningModels = []
            connectionStatus = .disconnected(error.localizedDescription)
            errorMessage = "無法連線到本機 Ollama 服務，請確認服務是否已啟動。"
        }
    }

    func refreshRunningModels() async {
        guard let baseURL = settings.baseURL else {
            runningModels = []
            return
        }

        do {
            runningModels = try await ollamaClient.fetchRunningModels(baseURL: baseURL)
        } catch {
            runningModels = []
        }
    }

    func chooseModel(_ name: String) {
        settings.selectedModel = name
    }
}

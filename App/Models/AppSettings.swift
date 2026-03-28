import Foundation

struct AppSettings: Codable, Equatable {
    var baseURLString: String
    var selectedModel: String
    var systemPrompt: String
    var temperature: Double
    var numCtx: Int
    var streamEnabled: Bool
    var disableThinkingForQwen: Bool
    var firstTokenTimeoutSeconds: Int

    static let `default` = AppSettings(
        baseURLString: "http://127.0.0.1:11434",
        selectedModel: "qwen3:4b",
        systemPrompt: "",
        temperature: 0.7,
        numCtx: 2048,
        streamEnabled: true,
        disableThinkingForQwen: true,
        firstTokenTimeoutSeconds: 30
    )

    var baseURL: URL? {
        URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var supportsThinkingToggle: Bool {
        selectedModel.localizedCaseInsensitiveContains("qwen3")
    }

    var usesThinkingAPI: Bool {
        supportsThinkingToggle
    }

    enum CodingKeys: String, CodingKey {
        case baseURLString
        case selectedModel
        case systemPrompt
        case temperature
        case numCtx
        case streamEnabled
        case disableThinkingForQwen
        case firstTokenTimeoutSeconds
    }

    init(
        baseURLString: String,
        selectedModel: String,
        systemPrompt: String,
        temperature: Double,
        numCtx: Int,
        streamEnabled: Bool,
        disableThinkingForQwen: Bool,
        firstTokenTimeoutSeconds: Int
    ) {
        self.baseURLString = baseURLString
        self.selectedModel = selectedModel
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.numCtx = numCtx
        self.streamEnabled = streamEnabled
        self.disableThinkingForQwen = disableThinkingForQwen
        self.firstTokenTimeoutSeconds = firstTokenTimeoutSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings.default

        baseURLString = try container.decodeIfPresent(String.self, forKey: .baseURLString) ?? defaults.baseURLString
        selectedModel = try container.decodeIfPresent(String.self, forKey: .selectedModel) ?? defaults.selectedModel
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? defaults.systemPrompt
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? defaults.temperature
        numCtx = try container.decodeIfPresent(Int.self, forKey: .numCtx) ?? defaults.numCtx
        streamEnabled = try container.decodeIfPresent(Bool.self, forKey: .streamEnabled) ?? defaults.streamEnabled
        disableThinkingForQwen = try container.decodeIfPresent(Bool.self, forKey: .disableThinkingForQwen) ?? defaults.disableThinkingForQwen
        firstTokenTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .firstTokenTimeoutSeconds) ?? defaults.firstTokenTimeoutSeconds
    }
}

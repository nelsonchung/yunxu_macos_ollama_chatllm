import Foundation

struct AppSettings: Codable, Equatable {
    var baseURLString: String
    var selectedModel: String
    var systemPrompt: String
    var temperature: Double
    var numCtx: Int
    var streamEnabled: Bool

    static let `default` = AppSettings(
        baseURLString: "http://127.0.0.1:11434",
        selectedModel: "qwen3:4b",
        systemPrompt: "",
        temperature: 0.7,
        numCtx: 2048,
        streamEnabled: true
    )

    var baseURL: URL? {
        URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

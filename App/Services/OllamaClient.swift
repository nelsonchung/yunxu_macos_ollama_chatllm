import Foundation

actor OllamaClient {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func healthCheck(baseURL: URL) async throws {
        _ = try await fetchTags(baseURL: baseURL)
    }

    func fetchTags(baseURL: URL) async throws -> [OllamaModelTag] {
        let request = try makeRequest(
            baseURL: baseURL,
            path: "/api/tags",
            method: "GET"
        )
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return decoded.models.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func streamChat(
        baseURL: URL,
        model: String,
        messages: [OllamaChatRequestMessage],
        settings: AppSettings,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws {
        let payload = OllamaChatRequest(
            model: model,
            messages: messages,
            stream: settings.streamEnabled,
            options: OllamaChatOptions(
                temperature: settings.temperature,
                numCtx: settings.numCtx
            )
        )

        let request = try makeRequest(
            baseURL: baseURL,
            path: "/api/chat",
            method: "POST",
            body: try JSONEncoder().encode(payload)
        )

        let (bytes, response) = try await urlSession.bytes(for: request)
        try validate(response: response, data: nil)

        for try await line in bytes.lines {
            if Task.isCancelled {
                throw CancellationError()
            }

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }

            let chunkData = Data(trimmed.utf8)
            let chunk = try JSONDecoder().decode(OllamaChatStreamChunk.self, from: chunkData)
            if let content = chunk.message?.content, !content.isEmpty {
                onChunk(content)
            }

            if chunk.done {
                return
            }
        }
    }

    private func makeRequest(
        baseURL: URL,
        path: String,
        method: String,
        body: Data? = nil
    ) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw OllamaClientError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    private func validate(response: URLResponse, data: Data?) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let data, let errorResponse = try? JSONDecoder().decode(OllamaErrorResponse.self, from: data) {
                throw OllamaClientError.serverError(errorResponse.error)
            }

            throw OllamaClientError.httpStatus(httpResponse.statusCode)
        }
    }
}

struct OllamaChatRequestMessage: Codable, Equatable {
    let role: String
    let content: String
}

private struct OllamaTagsResponse: Decodable {
    let models: [OllamaModelTag]
}

private struct OllamaChatRequest: Codable {
    let model: String
    let messages: [OllamaChatRequestMessage]
    let stream: Bool
    let options: OllamaChatOptions
}

private struct OllamaChatOptions: Codable {
    let temperature: Double
    let numCtx: Int

    enum CodingKeys: String, CodingKey {
        case temperature
        case numCtx = "num_ctx"
    }
}

private struct OllamaChatStreamChunk: Decodable {
    let message: OllamaChunkMessage?
    let done: Bool
}

private struct OllamaChunkMessage: Decodable {
    let role: String?
    let content: String?
}

private struct OllamaErrorResponse: Decodable {
    let error: String
}

enum OllamaClientError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case httpStatus(Int)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "The Ollama base URL is invalid."
        case .invalidResponse:
            return "The Ollama service returned an invalid response."
        case .httpStatus(let code):
            return "The Ollama service returned HTTP \(code)."
        case .serverError(let message):
            return message
        }
    }
}

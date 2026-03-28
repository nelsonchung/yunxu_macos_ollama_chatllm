# yunxu_macos_ollama_chatllm

Native macOS SwiftUI chat app for local Ollama models.

## Current Scope

The app currently implements:

- Ollama health/model discovery via `/api/tags`
- Running-model status via `/api/ps`
- Streaming chat via `/api/chat`
- Reasoning/thinking trace rendering for Qwen3 when Quick Response Mode is off
- Multi-conversation sidebar
- Local conversation persistence in Application Support
- Settings for base URL, model, system prompt, temperature, and context size
- Basic macOS chat UX with stop generation and keyboard send shortcut

## Requirements

- macOS
- Xcode 26 or later
- Swift 6
- Local Ollama service running on `http://127.0.0.1:11434`

## Build

```bash
swift build
```

## Open In Xcode

Open the repository folder directly in Xcode. This project is set up as a Swift Package with a macOS SwiftUI executable target.

## Default Settings

- Base URL: `http://127.0.0.1:11434`
- Model: `qwen3:4b`
- Temperature: `0.7`
- Context window: `2048`

## Persistence

App data is stored under:

```text
~/Library/Application Support/YunxuOllamaChat/
```

Conversation files are stored as JSON in the `Conversations` subdirectory, alongside the saved app settings.

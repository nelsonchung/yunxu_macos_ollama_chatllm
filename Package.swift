// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "yunxu_macos_ollama_chatllm",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "YunxuOllamaChat",
            targets: ["YunxuOllamaChat"]
        )
    ],
    targets: [
        .executableTarget(
            name: "YunxuOllamaChat",
            path: "App"
        )
    ]
)

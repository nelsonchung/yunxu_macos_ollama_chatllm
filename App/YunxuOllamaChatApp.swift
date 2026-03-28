import SwiftUI

@main
struct YunxuOllamaChatApp: App {
    @StateObject private var settingsViewModel: SettingsViewModel
    @StateObject private var conversationListViewModel: ConversationListViewModel
    @StateObject private var chatViewModel: ChatViewModel

    init() {
        let ollamaClient = OllamaClient()
        let conversationStore = ConversationStore()
        let settingsStore = SettingsStore()
        let settingsViewModel = SettingsViewModel(
            store: settingsStore,
            ollamaClient: ollamaClient
        )
        let conversationListViewModel = ConversationListViewModel(
            store: conversationStore
        )
        let chatViewModel = ChatViewModel(
            ollamaClient: ollamaClient,
            conversationStore: conversationStore,
            conversationsViewModel: conversationListViewModel,
            settingsViewModel: settingsViewModel
        )

        _settingsViewModel = StateObject(wrappedValue: settingsViewModel)
        _conversationListViewModel = StateObject(wrappedValue: conversationListViewModel)
        _chatViewModel = StateObject(wrappedValue: chatViewModel)
    }

    var body: some Scene {
        WindowGroup("Yunxu Ollama Chat") {
            ContentView(
                conversationListViewModel: conversationListViewModel,
                settingsViewModel: settingsViewModel,
                chatViewModel: chatViewModel
            )
            .frame(minWidth: 1080, minHeight: 720)
            .task {
                await chatViewModel.bootstrap()
            }
        }
        .windowResizability(.contentMinSize)
    }
}

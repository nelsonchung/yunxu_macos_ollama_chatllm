import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        // Swift Package GUI apps launched from Terminal may show a window
        // without immediately becoming the active foreground app.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct YunxuOllamaChatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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

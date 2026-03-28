import SwiftUI

struct ContentView: View {
    @ObservedObject var conversationListViewModel: ConversationListViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var chatViewModel: ChatViewModel

    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                viewModel: conversationListViewModel,
                defaultModel: settingsViewModel.settings.selectedModel
            )
        } detail: {
            ChatDetailView(
                conversation: conversationListViewModel.selectedConversation,
                draftText: $chatViewModel.draftText,
                isGenerating: chatViewModel.isGenerating,
                errorMessage: combinedErrorMessage,
                connectionStatus: settingsViewModel.connectionStatus,
                runningModels: settingsViewModel.runningModels,
                selectedModel: settingsViewModel.settings.selectedModel,
                onSend: chatViewModel.sendMessage,
                onStop: chatViewModel.cancelGeneration,
                onRetryConnection: chatViewModel.retryConnectionCheck,
                onRefreshRuntimeStatus: {
                    Task {
                        await settingsViewModel.refreshRunningModels()
                    }
                }
            )
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                statusBadge

                Button {
                    conversationListViewModel.createConversation(defaultModel: settingsViewModel.settings.selectedModel)
                } label: {
                    Label("New Chat", systemImage: "plus.bubble")
                }

                Button {
                    Task {
                        await settingsViewModel.refreshModels()
                    }
                } label: {
                    Label("Refresh Models", systemImage: "arrow.clockwise")
                }

                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: settingsViewModel)
        }
    }

    private var combinedErrorMessage: String? {
        chatViewModel.errorMessage
        ?? conversationListViewModel.errorMessage
        ?? settingsViewModel.errorMessage
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(settingsViewModel.connectionStatus.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial)
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch settingsViewModel.connectionStatus {
        case .connected:
            return .green
        case .checking:
            return .orange
        case .disconnected:
            return .red
        case .unknown:
            return .gray
        }
    }
}

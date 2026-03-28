import SwiftUI

struct ChatDetailView: View {
    let conversation: ChatConversation?
    @Binding var draftText: String
    let isGenerating: Bool
    let errorMessage: String?
    let connectionStatus: OllamaConnectionStatus
    let selectedModel: String
    let onSend: () -> Void
    let onStop: () -> Void
    let onRetryConnection: () -> Void

    var body: some View {
        Group {
            if let conversation {
                VStack(spacing: 0) {
                    header(for: conversation)
                    Divider()
                    messageList(for: conversation)
                    Divider()
                    MessageComposerView(
                        draftText: $draftText,
                        isGenerating: isGenerating,
                        onSend: onSend,
                        onStop: onStop
                    )
                }
            } else {
                ContentUnavailableView(
                    "No Conversation Selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Create a conversation to start chatting with your local model.")
                )
            }
        }
    }

    private func header(for conversation: ChatConversation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Model: \(conversation.modelName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let errorMessage {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(errorMessage)
                            .font(.subheadline)
                        if case .disconnected = connectionStatus {
                            Button("Retry Connection", action: onRetryConnection)
                                .buttonStyle(.link)
                        }
                    }
                }
                .padding(12)
                .background(Color.yellow.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(20)
    }

    private func messageList(for conversation: ChatConversation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(conversation.messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }
                }
                .padding(20)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onAppear {
                scrollToBottom(proxy: proxy, conversation: conversation)
            }
            .onChange(of: conversation.messages) { _, updatedMessages in
                scrollToBottom(proxy: proxy, conversation: conversation)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, conversation: ChatConversation) {
        guard let lastID = conversation.messages.last?.id else {
            return
        }

        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }
}

private struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .assistant {
                bubble
                Spacer(minLength: 60)
            } else {
                Spacer(minLength: 60)
                bubble
            }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(displayContent)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if message.status == .streaming {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: 640, alignment: .leading)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var title: String {
        switch message.role {
        case .assistant:
            return "Assistant"
        case .user:
            return "You"
        case .system:
            return "System"
        }
    }

    private var displayContent: String {
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && message.status == .streaming {
            return "Thinking..."
        }
        return message.content
    }

    private var backgroundColor: Color {
        switch message.role {
        case .assistant:
            return Color.blue.opacity(0.08)
        case .user:
            return Color.green.opacity(0.12)
        case .system:
            return Color.gray.opacity(0.12)
        }
    }
}

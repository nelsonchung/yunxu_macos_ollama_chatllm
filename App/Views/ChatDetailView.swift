import SwiftUI

struct ChatDetailView: View {
    let conversation: ChatConversation?
    @Binding var draftText: String
    let isGenerating: Bool
    let errorMessage: String?
    let connectionStatus: OllamaConnectionStatus
    let runningModels: [OllamaRunningModel]
    let contextUsage: ContextUsageSnapshot?
    let selectedModel: String
    let onSend: () -> Void
    let onStop: () -> Void
    let onRetryConnection: () -> Void
    let onRefreshRuntimeStatus: () -> Void
    @State private var showsRuntimeDetails = false

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
                    if let contextUsage {
                        ContextUsageView(snapshot: contextUsage)
                    }
                }
                Spacer()
            }

            runtimeStatusSection

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

    private var runtimeStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Running Models", systemImage: "cpu")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Refresh", action: onRefreshRuntimeStatus)
                    .buttonStyle(.link)
            }

            if runningModels.isEmpty {
                Text(connectionStatus == .connected ? "No models currently loaded in memory." : "Runtime status unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                DisclosureGroup(isExpanded: $showsRuntimeDetails) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(runningModels) { model in
                            RunningModelDetailRow(
                                model: model,
                                isSelected: model.name == selectedModel || model.model == selectedModel
                            )
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(runningModels) { model in
                            RunningModelSummaryRow(
                                model: model,
                                isSelected: model.name == selectedModel || model.model == selectedModel
                            )
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 14))
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

private struct ContextUsageView: View {
    let snapshot: ContextUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label("Context", systemImage: "text.quote")
                    .foregroundStyle(.secondary)

                Text("\(snapshot.messageCount) msgs")
                    .foregroundStyle(.secondary)

                Text("·")
                    .foregroundStyle(.tertiary)

                Text("\(snapshot.characterCount.formatted()) chars")
                    .foregroundStyle(.secondary)

                Text("·")
                    .foregroundStyle(.tertiary)

                Text("est. \(snapshot.estimatedTokenCount) / \(snapshot.contextWindow) tok")
                    .foregroundStyle(contextColor)

                Text("·")
                    .foregroundStyle(.tertiary)

                Text("left ~\(snapshot.remainingTokenEstimate)")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: barColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geometry.size.width * snapshot.utilizationRatio))
                }
            }
            .frame(height: 6)
        }
    }

    private var contextColor: Color {
        switch snapshot.utilizationRatio {
        case 0.8...:
            return .orange
        case 0.6...:
            return .yellow
        default:
            return .secondary
        }
    }

    private var barColors: [Color] {
        switch snapshot.utilizationRatio {
        case 0.8...:
            return [Color.orange.opacity(0.8), Color.red.opacity(0.85)]
        case 0.6...:
            return [Color.yellow.opacity(0.85), Color.orange.opacity(0.8)]
        default:
            return [Color.blue.opacity(0.65), Color.green.opacity(0.75)]
        }
    }
}

private struct MessageBubbleView: View {
    let message: ChatMessage

    private var resolvedDisplay: ChatMessageDisplay {
        message.resolvedDisplay
    }

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
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let responseModeLabel {
                            ResponseModeBadge(
                                text: responseModeLabel,
                                tone: responseModeTone
                            )
                        }
                    }

                    MessageTimingView(message: message)
                }

                Spacer()

                if let copyableText, !copyableText.isEmpty {
                    Button {
                        Clipboard.copy(copyableText)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Copy message")
                }
            }

            if let thinkingContent, !thinkingContent.isEmpty {
                ThoughtSectionView(
                    content: thinkingContent,
                    isStreaming: message.status == .streaming && answerContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            if !displayContent.isEmpty {
                MessageContentView(
                    content: displayContent,
                    isStreaming: message.status == .streaming
                )
            } else if message.status == .streaming, thinkingContent != nil {
                Label("Generating final answer...", systemImage: "ellipsis.bubble")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

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
        let trimmed = answerContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && message.status == .streaming {
            return thinkingContent == nil ? "Thinking..." : ""
        }
        return answerContent
    }

    private var answerContent: String {
        resolvedDisplay.answer
    }

    private var thinkingContent: String? {
        let trimmed = resolvedDisplay.thinking?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return resolvedDisplay.thinking
        }
        return nil
    }

    private var copyableText: String? {
        let answer = answerContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !answer.isEmpty {
            return answerContent
        }
        return thinkingContent
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

    private var responseModeLabel: String? {
        guard message.role == .assistant else {
            return nil
        }

        if thinkingContent != nil {
            return "Thinking trace detected"
        }

        if message.status == .streaming {
            return nil
        }

        let trimmedAnswer = answerContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty else {
            return nil
        }

        return "Direct answer only"
    }

    private var responseModeTone: ResponseModeBadge.Tone {
        thinkingContent != nil ? .thinking : .direct
    }
}

private struct RunningModelSummaryRow: View {
    let model: OllamaRunningModel
    let isSelected: Bool

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack(spacing: 8) {
            Text(model.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .lineLimit(1)

            Text("·")
                .foregroundStyle(.tertiary)

            Text(model.processorLabel)
                .foregroundStyle(.secondary)

            Text("·")
                .foregroundStyle(.tertiary)

            Text("ctx \(model.contextLength)")
                .foregroundStyle(.secondary)

            Text("·")
                .foregroundStyle(.tertiary)

            Text("VRAM \(model.vramLabel)")
                .foregroundStyle(.secondary)

            Text("·")
                .foregroundStyle(.tertiary)

            Text(expirationLabel)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var expirationLabel: String {
        "until \(Self.relativeFormatter.localizedString(for: model.expiresAt, relativeTo: .now))"
    }
}

private struct RunningModelDetailRow: View {
    let model: OllamaRunningModel
    let isSelected: Bool

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        HStack(spacing: 10) {
            Text(model.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)

            if !model.summaryLabel.isEmpty {
                Text(model.summaryLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(model.processorLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("ctx \(model.contextLength)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("size \(model.sizeLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("VRAM \(model.vramLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("unloads \(Self.relativeFormatter.localizedString(for: model.expiresAt, relativeTo: .now))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MessageTimingView: View {
    let message: ChatMessage

    var body: some View {
        TimelineView(.periodic(from: message.createdAt, by: 0.5)) { context in
            Text(metadataText(now: context.date))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func metadataText(now: Date) -> String {
        var parts = [message.createdAt.formatted(date: .omitted, time: .standard)]

        if let duration = duration(now: now) {
            parts.append(durationText(duration))
        }

        return parts.joined(separator: " · ")
    }

    private func duration(now: Date) -> TimeInterval? {
        guard message.role == .assistant else {
            return nil
        }

        if let completedAt = message.completedAt {
            return completedAt.timeIntervalSince(message.createdAt)
        }

        if message.status == .streaming {
            return now.timeIntervalSince(message.createdAt)
        }

        return nil
    }

    private func durationText(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return "\(Int(duration * 1000)) ms"
        }

        return String(format: "%.1f s", duration)
    }
}

private struct MessageContentView: View {
    let content: String
    let isStreaming: Bool

    private var segments: [MarkdownSegment] {
        MarkdownRenderer.segments(from: content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .prose(let attributed):
                    Text(attributed)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .codeBlock(let language, let code):
                    CodeBlockView(language: language, code: code)
                }
            }

            if isStreaming && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Thinking...")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ThoughtSectionView: View {
    let content: String
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Thinking", systemImage: "brain")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Clipboard.copy(content)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy thinking trace")
            }

            MessageContentView(content: content, isStreaming: isStreaming)
        }
        .padding(12)
        .background(Color.orange.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct ResponseModeBadge: View {
    enum Tone {
        case thinking
        case direct
    }

    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(backgroundColor)
            .clipShape(Capsule())
    }

    private var foregroundColor: Color {
        switch tone {
        case .thinking:
            return Color.orange.opacity(0.95)
        case .direct:
            return .secondary
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .thinking:
            return Color.orange.opacity(0.12)
        case .direct:
            return Color.primary.opacity(0.06)
        }
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(languageLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Clipboard.copy(code)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.04))

            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color.black.opacity(0.08))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.08))
        }
    }

    private var languageLabel: String {
        if let language, !language.isEmpty {
            return language
        }

        return "code"
    }
}

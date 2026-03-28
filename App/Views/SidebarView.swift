import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: ConversationListViewModel
    let defaultModel: String

    var body: some View {
        List(selection: $viewModel.selectedConversationID) {
            ForEach(viewModel.conversations) { conversation in
                VStack(alignment: .leading, spacing: 6) {
                    Text(conversation.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .tag(conversation.id)
                .contextMenu {
                    Button("Delete Conversation", role: .destructive) {
                        viewModel.deleteConversations([conversation.id], fallbackModel: defaultModel)
                    }
                }
            }
            .onDelete { offsets in
                viewModel.deleteConversations(at: offsets, fallbackModel: defaultModel)
            }
        }
        .navigationTitle("Conversations")
    }
}

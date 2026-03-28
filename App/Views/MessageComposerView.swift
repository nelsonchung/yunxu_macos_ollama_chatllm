import SwiftUI

struct MessageComposerView: View {
    @Binding var draftText: String
    let isGenerating: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draftText)
                    .font(.body)
                    .focused($isEditorFocused)
                    .frame(minHeight: 100, maxHeight: 180)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                if draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Message your local Ollama model...")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Text("Command + Return to send")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if isGenerating {
                    Button("Stop", action: onStop)
                        .keyboardShortcut(.cancelAction)
                }

                Button("Send", action: onSend)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(isGenerating || draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .background(.regularMaterial)
        .onAppear {
            requestEditorFocus()
        }
        .onChange(of: isGenerating) { _, newValue in
            if !newValue {
                requestEditorFocus()
            }
        }
    }

    private func requestEditorFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isEditorFocused = true
        }
    }
}

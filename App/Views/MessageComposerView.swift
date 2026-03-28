import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MessageComposerView: View {
    @Binding var draftText: String
    @Binding var draftImages: [ChatImageAttachment]
    let isGenerating: Bool
    let onAppendImages: ([ChatImageAttachment]) -> Void
    let onRemoveImage: (UUID) -> Void
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var isEditorFocused: Bool
    @State private var isDropTargeted = false
    @State private var showingFileImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !draftImages.isEmpty {
                DraftAttachmentStrip(
                    images: draftImages,
                    onRemoveImage: onRemoveImage
                )
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $draftText)
                    .font(.body)
                    .focused($isEditorFocused)
                    .frame(minHeight: 100, maxHeight: 180)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(editorBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(isDropTargeted ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.06))
                    }

                if draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draftImages.isEmpty {
                    Text("Message your local Ollama model or paste / drop an image...")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .onPasteCommand(of: pasteboardTypes) { _ in
                let attachments = ImageAttachmentSupport.attachmentsFromPasteboard()
                guard !attachments.isEmpty else {
                    return
                }

                onAppendImages(attachments)
            }
            .onDrop(of: dropTypes, isTargeted: $isDropTargeted) { providers in
                Task {
                    let attachments = await ImageAttachmentSupport.loadAttachments(from: providers)
                    await MainActor.run {
                        onAppendImages(attachments)
                    }
                }
                return true
            }

            HStack {
                Button {
                    let attachments = ImageAttachmentSupport.attachmentsFromPasteboard()
                    onAppendImages(attachments)
                } label: {
                    Label("Paste Image", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.plain)

                Button {
                    showingFileImporter = true
                } label: {
                    Label("Choose Image", systemImage: "paperclip")
                }
                .buttonStyle(.plain)

                Text("Command + V to paste a screenshot, or drag image files here")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if isGenerating {
                    Button("Stop", action: onStop)
                        .keyboardShortcut(.cancelAction)
                }

                Button("Send", action: onSend)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(isGenerating || sendDisabled)
            }
        }
        .padding(20)
        .background(.regularMaterial)
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else {
                return
            }

            let attachments = urls.compactMap(ImageAttachmentSupport.loadAttachment(from:))
            onAppendImages(attachments)
        }
        .onAppear {
            requestEditorFocus()
        }
        .onChange(of: isGenerating) { _, newValue in
            if !newValue {
                requestEditorFocus()
            }
        }
    }

    private var sendDisabled: Bool {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draftImages.isEmpty
    }

    private var editorBackground: Color {
        if isDropTargeted {
            return Color.accentColor.opacity(0.08)
        }

        return Color(nsColor: .textBackgroundColor)
    }

    private var pasteboardTypes: [UTType] {
        [.png, .jpeg, .tiff, .gif, .webP, .fileURL]
    }

    private var dropTypes: [String] {
        pasteboardTypes.map(\.identifier)
    }

    private func requestEditorFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isEditorFocused = true
        }
    }
}

private struct DraftAttachmentStrip: View {
    let images: [ChatImageAttachment]
    let onRemoveImage: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(images) { image in
                    DraftAttachmentThumbnail(
                        image: image,
                        onRemove: {
                            onRemoveImage(image.id)
                        }
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct DraftAttachmentThumbnail: View {
    let image: ChatImageAttachment
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let nsImage = NSImage(data: image.data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.08))
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, Color.black.opacity(0.55))
            }
            .buttonStyle(.plain)
            .padding(6)
        }
    }
}

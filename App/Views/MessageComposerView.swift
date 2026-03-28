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

    @State private var shouldFocusEditor = false
    @State private var isDropTargeted = false
    @State private var showingFileImporter = false
    @State private var attachmentFeedbackMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !draftImages.isEmpty {
                DraftAttachmentStrip(
                    images: draftImages,
                    onRemoveImage: onRemoveImage
                )
            }

            ZStack(alignment: .topLeading) {
                ComposerTextView(
                    text: $draftText,
                    shouldFocus: $shouldFocusEditor,
                    onPasteImages: { attachments in
                        guard !attachments.isEmpty else {
                            return
                        }

                        onAppendImages(attachments)
                        showAttachmentFeedback(for: attachments.count, action: "Pasted")
                    }
                )
                    .frame(minHeight: 100, maxHeight: 180)
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
                showAttachmentFeedback(for: attachments.count, action: "Pasted")
            }
            .onDrop(of: dropTypes, isTargeted: $isDropTargeted) { providers in
                Task {
                    let attachments = await ImageAttachmentSupport.loadAttachments(from: providers)
                    await MainActor.run {
                        onAppendImages(attachments)
                        if !attachments.isEmpty {
                            showAttachmentFeedback(for: attachments.count, action: "Added")
                        }
                    }
                }
                return true
            }

            HStack {
                Button {
                    let attachments = ImageAttachmentSupport.attachmentsFromPasteboard()
                    onAppendImages(attachments)
                    if !attachments.isEmpty {
                        showAttachmentFeedback(for: attachments.count, action: "Pasted")
                    }
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

            if let attachmentFeedbackMessage {
                Text(attachmentFeedbackMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .move(edge: .top)))
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
            if !attachments.isEmpty {
                showAttachmentFeedback(for: attachments.count, action: "Added")
            }
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
            shouldFocusEditor = true
        }
    }

    private func showAttachmentFeedback(for count: Int, action: String) {
        let noun = count == 1 ? "image" : "images"
        withAnimation(.easeOut(duration: 0.16)) {
            attachmentFeedbackMessage = "\(action) \(count) \(noun)"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeOut(duration: 0.2)) {
                attachmentFeedbackMessage = nil
            }
        }
    }
}

private struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var shouldFocus: Bool
    let onPasteImages: ([ChatImageAttachment]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let textView = PasteAwareTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.onPasteImages = onPasteImages

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? PasteAwareTextView else {
            return
        }

        if textView.string != text {
            textView.string = text
        }

        textView.onPasteImages = onPasteImages

        if shouldFocus, nsView.window?.firstResponder !== textView {
            nsView.window?.makeFirstResponder(textView)
            DispatchQueue.main.async {
                shouldFocus = false
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            text = textView.string
        }
    }
}

private final class PasteAwareTextView: NSTextView {
    var onPasteImages: (([ChatImageAttachment]) -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.readablePasteboardTypes + supportedImagePasteboardTypes
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let isCommandV = event.type == .keyDown
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            && event.charactersIgnoringModifiers?.lowercased() == "v"

        if isCommandV, consumePasteboardImages() {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func paste(_ sender: Any?) {
        if consumePasteboardImages() {
            return
        }

        super.paste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        if consumePasteboardImages() {
            return
        }

        super.pasteAsPlainText(sender)
    }

    override func pasteAsRichText(_ sender: Any?) {
        if consumePasteboardImages() {
            return
        }

        super.pasteAsRichText(sender)
    }

    override func readSelection(from pboard: NSPasteboard) -> Bool {
        if consumePasteboardImages(from: pboard) {
            return true
        }

        return super.readSelection(from: pboard)
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if supportedImagePasteboardTypes.contains(type), consumePasteboardImages(from: pboard) {
            return true
        }

        return super.readSelection(from: pboard, type: type)
    }

    private var supportedImagePasteboardTypes: [NSPasteboard.PasteboardType] {
        [
            NSPasteboard.PasteboardType(UTType.png.identifier),
            NSPasteboard.PasteboardType(UTType.jpeg.identifier),
            NSPasteboard.PasteboardType(UTType.tiff.identifier),
            NSPasteboard.PasteboardType(UTType.gif.identifier),
            NSPasteboard.PasteboardType(UTType.webP.identifier),
            .fileURL
        ]
    }

    private func consumePasteboardImages(from pasteboard: NSPasteboard = .general) -> Bool {
        let attachments = ImageAttachmentSupport.attachments(from: pasteboard)
        guard !attachments.isEmpty else {
            return false
        }

        onPasteImages?(attachments)
        return true
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

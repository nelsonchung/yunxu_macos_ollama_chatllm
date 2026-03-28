import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                TextField("Ollama Base URL", text: $viewModel.settings.baseURLString)

                Picker("Model", selection: $viewModel.settings.selectedModel) {
                    ForEach(modelOptions, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(viewModel.settings.temperature.formatted(.number.precision(.fractionLength(2))))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $viewModel.settings.temperature, in: 0...1.5, step: 0.05)
                }

                Stepper(
                    "Context Window: \(viewModel.settings.numCtx)",
                    value: $viewModel.settings.numCtx,
                    in: 512...8192,
                    step: 512
                )

                Toggle("Enable Streaming", isOn: $viewModel.settings.streamEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    Text("System Prompt")
                    TextEditor(text: $viewModel.settings.systemPrompt)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .formStyle(.grouped)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Refresh Models") {
                    Task {
                        await viewModel.refreshModels()
                    }
                }

                Spacer()

                Button("Save") {
                    Task {
                        await viewModel.save()
                        await viewModel.refreshModels()
                    }
                }
                .keyboardShortcut(.defaultAction)

                Button("Done") {
                    dismiss()
                }
            }
        }
        .padding(24)
        .frame(width: 520, height: 560)
    }

    private var modelOptions: [String] {
        let merged = [viewModel.settings.selectedModel] + viewModel.availableModels
        return Array(NSOrderedSet(array: merged)) as? [String] ?? merged
    }
}

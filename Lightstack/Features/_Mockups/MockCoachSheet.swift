import SwiftUI

struct MockCoachSheet: View {
    @Binding var isPresented: Bool
    @State private var draftText: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: ModernTheme.spacingM) {
                        ForEach(MockData.coachMessages) { message in
                            ChatBubble(message: message)
                        }
                    }
                    .padding(.horizontal, ModernTheme.spacingM)
                    .padding(.vertical, ModernTheme.spacingS)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(MockData.coachSuggestions, id: \.self) { suggestion in
                            Button(action: {}) {
                                Text(suggestion)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(ModernTheme.accent.opacity(0.12))
                                    .foregroundStyle(ModernTheme.accent)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding(.horizontal, ModernTheme.spacingM)
                .padding(.vertical, ModernTheme.spacingS)

                Divider()

                HStack(spacing: ModernTheme.spacingS) {
                    TextField("Message your coach...", text: $draftText, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())

                    Button(action: {}) {
                        Image(systemName: "arrow.up.circle.fill")
                            .resizable()
                            .frame(width: 36, height: 36)
                            .foregroundStyle(ModernTheme.accent)
                    }
                    .disabled(draftText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, ModernTheme.spacingM)
                .padding(.vertical, ModernTheme.spacingS)
                .background(.regularMaterial)
            }
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

private struct ChatBubble: View {
    let message: MockCoachMessage

    var body: some View {
        GeometryReader { geo in
            Group {
                if message.role == .coach {
                    HStack(alignment: .bottom, spacing: ModernTheme.spacingS) {
                        Circle()
                            .fill(ModernTheme.accent.opacity(0.15))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Image(systemName: "sparkles")
                                    .font(.system(size: 13))
                                    .foregroundStyle(ModernTheme.accent)
                            )

                        Text(message.text)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .frame(maxWidth: geo.size.width * 0.80, alignment: .leading)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack {
                        Spacer(minLength: 0)

                        Text(message.text)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(ModernTheme.accent)
                            .foregroundStyle(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .frame(maxWidth: geo.size.width * 0.80, alignment: .trailing)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("Light") {
    StatefulPreviewWrapper(true) { binding in
        Color.gray.sheet(isPresented: binding) {
            MockCoachSheet(isPresented: binding)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

#Preview("Dark") {
    StatefulPreviewWrapper(true) { binding in
        Color.gray.sheet(isPresented: binding) {
            MockCoachSheet(isPresented: binding)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
    .preferredColorScheme(.dark)
}

private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    let content: (Binding<Value>) -> Content
    init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initial)
        self.content = content
    }
    var body: some View { content($value) }
}

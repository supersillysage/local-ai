import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    @State private var copied = false

    var body: some View {
        HStack(alignment: .top) {
            if message.role == "user" { Spacer(minLength: 60) }

            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 4) {
                if message.role == "user" {
                    userBubble
                } else {
                    assistantBubble
                }
            }

            if message.role != "user" { Spacer(minLength: 16) }
        }
    }

    private var userBubble: some View {
        Text(message.content)
            .font(.system(size: 15))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let thinking = message.thinkingContent, !thinking.isEmpty {
                ThinkingContainer(thinkingText: thinking, isThinking: false)
            }

            if !message.content.isEmpty {
                Text(LocalizedStringKey(message.content))
                    .font(.system(size: 15))
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    Button {
                        UIPasteboard.general.string = message.content
                        withAnimation(.easeInOut(duration: 0.2)) { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeInOut(duration: 0.2)) { copied = false }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11))
                            if copied {
                                Text("Copied")
                                    .font(.system(size: 11))
                            }
                        }
                        .foregroundStyle(copied ? .green : Color(.systemGray3))
                    }

                    if let stats = message.stats {
                        StatsBar(stats: stats)
                    }
                }
            }
        }
    }
}

struct ThinkingContainer: View {
    let thinkingText: String
    let isThinking: Bool

    @State private var isExpanded = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    if isThinking {
                        ThinkingPulse()
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Text(isThinking ? "Thinking..." : "Thought")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isThinking ? .primary : .secondary)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)

                    Spacer()

                    if !isThinking && !thinkingText.isEmpty {
                        Button {
                            UIPasteboard.general.string = thinkingText
                            withAnimation(.easeInOut(duration: 0.2)) { copied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation(.easeInOut(duration: 0.2)) { copied = false }
                            }
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundStyle(copied ? .green : Color(.systemGray3))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isExpanded && !thinkingText.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(thinkingText)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Color.clear
                                .frame(height: 1)
                                .id("thinkingBottom")
                        }
                        .padding(.bottom, 10)
                    }
                    .frame(maxHeight: isThinking ? 120 : 400)
                    .onChange(of: thinkingText) {
                        if isThinking {
                            proxy.scrollTo("thinkingBottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color(.systemGray6).opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            isExpanded = isThinking
        }
        .onChange(of: isThinking) { _, newValue in
            if !newValue && isExpanded {
                withAnimation(.easeInOut(duration: 0.3).delay(0.5)) {
                    isExpanded = false
                }
            }
        }
    }
}

struct ThinkingPulse: View {
    @State private var isPulsing = false

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 11))
            .foregroundStyle(.blue)
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

struct ThinkingIndicator: View {
    @State private var dotCount = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color(.systemGray3))
                        .frame(width: 8, height: 8)
                        .opacity(i <= dotCount ? 1 : 0.3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .onReceive(timer) { _ in
                dotCount = (dotCount + 1) % 3
            }

            Spacer(minLength: 60)
        }
    }
}

struct StatsBar: View {
    let stats: GenerationStats

    var body: some View {
        HStack(spacing: 6) {
            Text("\(String(format: "%.1f", stats.tokensPerSecond)) tok/s")
            Text("\(stats.totalTokens) tokens")
            Text(String(format: "%.1fs total", Double(stats.totalTokens) / max(stats.tokensPerSecond, 0.1)))
            Text(String(format: "%.2fs TTFT", stats.timeToFirstToken))
        }
        .font(.system(size: 10))
        .foregroundStyle(Color(.systemGray3))
    }
}

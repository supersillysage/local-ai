import Foundation
import MLX
import MLXLLM
import MLXLMCommon

struct GenerationStats {
    let tokensPerSecond: Double
    let timeToFirstToken: Double
    let totalTokens: Int
}

@MainActor
final class LLMEngine: ObservableObject {
    @Published var output = ""
    @Published var thinkingText = ""
    @Published var answerText = ""
    @Published var isThinking = false
    @Published var isGenerating = false
    @Published var activeThinkingMode = false
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0
    @Published var stats: GenerationStats?
    @Published var stoppedByRepetition = false

    private var modelContainer: ModelContainer?
    private var generateTask: Task<Void, Never>?
    private(set) var activeModel: ModelConfig?

    private let thinkingBudget = 400

    func loadModel(_ config: ModelConfig) async throws {
        isLoading = true
        loadingProgress = 0
        defer { isLoading = false }

        MLX.Memory.cacheLimit = 20 * 1024 * 1024

        let modelConfig = ModelConfiguration(id: config.huggingFaceRepo)

        modelContainer = try await LLMModelFactory.shared.loadContainer(
            configuration: modelConfig
        ) { [weak self] progress in
            Task { @MainActor in
                self?.loadingProgress = progress.fractionCompleted
            }
        }

        activeModel = config
    }

    func generate(messages: [[String: String]], maxTokens: Int = 512, enableThinking: Bool = true) {
        guard let container = modelContainer else { return }
        guard !isGenerating else { return }

        isGenerating = true
        activeThinkingMode = enableThinking
        output = ""
        thinkingText = ""
        answerText = ""
        isThinking = enableThinking
        stats = nil
        stoppedByRepetition = false

        generateTask = Task {
            let ttftStart = Date()
            var firstTokenReceived = false
            var ttft: Double = 0
            var tokenCount = 0

            do {
                let stream: AsyncStream<Generation> = try await container.perform { (context: ModelContext) in
                    let additionalContext: [String: Any] = [
                        "enable_thinking": enableThinking
                    ]
                    let promptTokens = try context.tokenizer.applyChatTemplate(
                        messages: messages,
                        chatTemplate: nil,
                        addGenerationPrompt: true,
                        truncation: false,
                        maxLength: nil,
                        tools: nil,
                        additionalContext: additionalContext
                    )
                    let input = LMInput(tokens: MLXArray(promptTokens))
                    let thinkingOverhead = enableThinking ? self.thinkingBudget : 0
                    let parameters = GenerateParameters(
                        maxTokens: maxTokens + thinkingOverhead,
                        temperature: enableThinking ? 0.6 : 0.7,
                        topP: enableThinking ? 0.95 : 0.8
                    )
                    return try MLXLMCommon.generate(
                        input: input,
                        parameters: parameters,
                        context: context
                    )
                }

                var needsPhase2 = false

                for await generation in stream {
                    if Task.isCancelled { break }

                    switch generation {
                    case .chunk(let text):
                        if !firstTokenReceived {
                            ttft = Date().timeIntervalSince(ttftStart)
                            firstTokenReceived = true
                        }
                        tokenCount += 1
                        output += text

                        if enableThinking {
                            updateParsedOutput()

                            if !isThinking && !answerText.isEmpty {
                                if tokenCount % 20 == 0, let trimmed = detectRepetition(answerText) {
                                    answerText = trimmed
                                    stoppedByRepetition = true
                                }
                            }

                            if isThinking && tokenCount >= thinkingBudget {
                                isThinking = false
                                thinkingText = trimToLastSentence(thinkingText)
                                needsPhase2 = true
                            }
                        } else {
                            if tokenCount % 20 == 0, let trimmed = detectRepetition(output) {
                                output = trimmed
                                stoppedByRepetition = true
                            }
                        }

                    case .info(let info):
                        if !enableThinking {
                            stats = GenerationStats(
                                tokensPerSecond: info.tokensPerSecond,
                                timeToFirstToken: ttft,
                                totalTokens: info.generationTokenCount
                            )
                        }

                    default:
                        break
                    }

                    if stoppedByRepetition || needsPhase2 { break }
                }

                // Phase 2: only when thinking was enabled but model never hit </think>
                if needsPhase2 && !Task.isCancelled {
                    let answerStream: AsyncStream<Generation> = try await container.perform { (context: ModelContext) in
                        let additionalContext: [String: Any] = ["enable_thinking": false]
                        let promptTokens = try context.tokenizer.applyChatTemplate(
                            messages: messages,
                            chatTemplate: nil,
                            addGenerationPrompt: true,
                            truncation: false,
                            maxLength: nil,
                            tools: nil,
                            additionalContext: additionalContext
                        )
                        let input = LMInput(tokens: MLXArray(promptTokens))
                        let parameters = GenerateParameters(
                            maxTokens: maxTokens,
                            temperature: 0.7,
                            topP: 0.8
                        )
                        return try MLXLMCommon.generate(
                            input: input,
                            parameters: parameters,
                            context: context
                        )
                    }

                    for await generation in answerStream {
                        if Task.isCancelled { break }

                        switch generation {
                        case .chunk(let text):
                            tokenCount += 1
                            answerText += text

                            if tokenCount % 20 == 0, let trimmed = detectRepetition(answerText) {
                                answerText = trimmed
                                stoppedByRepetition = true
                            }

                        case .info:
                            break

                        default:
                            break
                        }

                        if stoppedByRepetition { break }
                    }
                }

                if stats == nil {
                    let elapsed = Date().timeIntervalSince(ttftStart)
                    stats = GenerationStats(
                        tokensPerSecond: elapsed > 0 ? Double(tokenCount) / elapsed : 0,
                        timeToFirstToken: ttft,
                        totalTokens: tokenCount
                    )
                }
            } catch {
                if !Task.isCancelled {
                    answerText += "\n[Error: \(error.localizedDescription)]"
                }
            }

            isGenerating = false
        }
    }

    func cancelGeneration() {
        generateTask?.cancel()
        generateTask = nil
        isGenerating = false
    }

    private func updateParsedOutput() {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let closeRange = trimmed.range(of: "</think>") {
            thinkingText = String(trimmed[..<closeRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            answerText = String(trimmed[closeRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            isThinking = false
        } else {
            thinkingText = trimmed
            isThinking = true
        }
    }

    private func trimToLastSentence(_ text: String) -> String {
        let endings: [Character] = [".", "!", "?", ":", "\n"]
        // Search backwards for the last sentence-ending character
        for i in text.indices.reversed() {
            if endings.contains(text[i]) {
                let trimmed = String(text[...i]).trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count > 20 { return trimmed }
            }
        }
        return text
    }

    private func detectRepetition(_ text: String) -> String? {
        guard text.count > 60 else { return nil }

        for windowSize in [40, 30, 20, 15] {
            guard text.count > windowSize * 3 else { continue }

            let suffix = String(text.suffix(windowSize))
            let searchArea = String(text.dropLast(windowSize))

            var count = 0
            var searchFrom = searchArea.startIndex
            while let range = searchArea.range(of: suffix, range: searchFrom..<searchArea.endIndex) {
                count += 1
                searchFrom = range.upperBound
                if count >= 2 { break }
            }

            if count >= 2 {
                if let firstRange = text.range(of: suffix) {
                    let afterFirst = text[firstRange.upperBound...]
                    if let secondRange = afterFirst.range(of: suffix) {
                        return String(text[..<secondRange.upperBound])
                    }
                }
                return searchArea
            }
        }

        return nil
    }
}

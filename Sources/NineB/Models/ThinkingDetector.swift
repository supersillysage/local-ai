import Foundation

enum ThinkingDetector {
    /// Returns true if the query is complex enough to benefit from reasoning.
    static func needsThinking(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = lower.split(separator: " ").count

        // Very short queries never need thinking
        if wordCount <= 3 { return false }

        // Check complex patterns first (before simple patterns reject them)
        let complexPatterns = [
            "compare", "contrast", "difference between",
            "explain", "how does", "how do",
            "pros and cons", "advantages", "disadvantages",
            "analyze", "evaluate", "recommend",
            "should i", "what should", "help me decide",
            "step by step", "walk me through",
            "write a", "draft a", "create a",
            "debug", "fix this", "what's wrong",
            "summarize", "break down", "why does", "why do", "why is",
        ]
        for pattern in complexPatterns {
            if lower.contains(pattern) { return true }
        }

        // Simple factual patterns — direct answers, no reasoning needed
        let simplePatterns = [
            "what is the", "what's the", "what are the",
            "who is", "who are", "who was", "who won",
            "where is", "where are", "where was",
            "when is", "when was", "when did", "when does",
            "capital of", "population of", "president of",
            "how old is", "how tall is", "how much does",
            "define ", "meaning of", "translate ",
            "weather in", "time in", "price of",
        ]
        for pattern in simplePatterns {
            if lower.contains(pattern) && wordCount < 12 { return false }
        }

        // Longer queries likely benefit from reasoning
        if wordCount >= 12 { return true }

        // Default: skip thinking for medium-length simple queries
        return false
    }
}

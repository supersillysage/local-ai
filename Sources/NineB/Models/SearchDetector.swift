import Foundation

enum SearchDetector {
    /// Returns true if the prompt likely needs web search results for a good answer.
    static func needsSearch(_ text: String) -> Bool {
        let lower = text.lowercased()

        // URL detection
        if lower.range(of: #"https?://"#, options: .regularExpression) != nil { return true }
        if lower.contains("www.") { return true }

        // Temporal keywords
        let temporal = ["today", "latest", "current", "currently", "right now",
                        "this week", "this month", "this year", "yesterday",
                        "recent", "recently", "2025", "2026", "tonight", "tomorrow"]
        for keyword in temporal {
            if lower.contains(keyword) { return true }
        }

        // Info-seeking patterns
        let patterns = [
            "who is", "who are", "who was", "who won",
            "what happened", "what is the price", "how much does", "how much is",
            "price of", "stock price", "market cap",
            "weather in", "weather for", "forecast",
            "news about", "latest news", "breaking",
            "score of", "game score", "match result",
            "release date", "when does", "when did", "when will",
            "search for", "look up", "google", "find me",
        ]
        for pattern in patterns {
            if lower.contains(pattern) { return true }
        }

        // Location/business queries — restaurants, stores, places, addresses
        let locationPatterns = [
            "best ", "top ", "nearest ", "closest ",
            "where is", "where can i", "where to",
            "address", "phone number", "hours",
            "restaurant", "cafe", "bar", "store", "shop", "hotel",
            "directions to", "how to get to",
            "open now", "near me", "in raleigh", "in new york",
            "reviews", "rating", "menu",
        ]
        for pattern in locationPatterns {
            if lower.contains(pattern) { return true }
        }

        // Question words + proper nouns or specific entities (likely factual lookup)
        let questionStarters = ["what is", "what are", "what's", "who is", "who's",
                                "how do i", "how does", "how to", "is there",
                                "can you find", "find ", "tell me about"]
        for starter in questionStarters {
            if lower.contains(starter) { return true }
        }

        return false
    }
}

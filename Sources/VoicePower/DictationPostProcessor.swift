import Foundation

enum DictationPostProcessor {
    static func format(_ text: String, autoPunctuation: Bool) -> String {
        var result = normalizeWhitespace(in: text)
        guard autoPunctuation else {
            return result
        }

        let alreadyHasPunctuation = result.range(of: "[，。！？,.!?]", options: .regularExpression) != nil
        if !alreadyHasPunctuation {
            result = addQuestionBreaks(in: result)
            result = addClauseCommas(in: result)
        }
        result = addTerminalPunctuation(in: result)
        result = cleanupSpacingAroundPunctuation(in: result)
        return result
    }

    private static func normalizeWhitespace(in text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func addQuestionBreaks(in text: String) -> String {
        var result = text
        let patterns: [(String, String)] = [
            ("([吗呢么呀])(?=(如果|我想|怎么|为什么|能不能|可不可以|要不要|是否|还有|那|另外))", "$1？"),
            ("(\\b(?:why|how|what|when|where|who|can|could|would|should|do|does|did|is|are|will)\\b[^.?!。！？]*)(?=\\b(?:if|then|also|and)\\b)", "$1? "),
        ]

        for (pattern, template) in patterns {
            result = result.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }

        return result
    }

    private static func addClauseCommas(in text: String) -> String {
        var result = text
        let chineseConnectors = ["因为", "所以", "但是", "不过", "然后", "而且", "如果", "其实", "另外"]

        for connector in chineseConnectors {
            let pattern = "(?<!^)(?<![，。！？,.!?\\s])\(NSRegularExpression.escapedPattern(for: connector))"
            result = result.replacingOccurrences(of: pattern, with: "，\(connector)", options: .regularExpression)
        }

        result = result.replacingOccurrences(
            of: "(?<![,，])\\s+(because|but|however|so|then)\\b",
            with: ", $1",
            options: [.regularExpression, .caseInsensitive]
        )

        return result
    }

    private static func addTerminalPunctuation(in text: String) -> String {
        guard let lastScalar = text.unicodeScalars.last else {
            return text
        }

        if CharacterSet(charactersIn: "。！？.!?").contains(lastScalar) {
            return text
        }

        let containsChinese = text.range(of: "\\p{Han}", options: .regularExpression) != nil
        let looksLikeQuestion = text.range(
            of: "(为什么|怎么|如何|吗$|呢$|么$|谁|什么|哪|哪里|哪儿|多少|能不能|可不可以|要不要|是否|^(why|how|what|when|where|who|can|could|would|should|do|does|did|is|are|will)\\b)",
            options: [.regularExpression, .caseInsensitive]
        ) != nil

        if looksLikeQuestion {
            return text + (containsChinese ? "？" : "?")
        }

        return text + (containsChinese ? "。" : ".")
    }

    private static func cleanupSpacingAroundPunctuation(in text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+([，。！？,.!?])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "([，。！？])(?=[A-Za-z])", with: "$1 ", options: .regularExpression)
            .replacingOccurrences(of: "([.?!])(?=[A-Za-z])", with: "$1 ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

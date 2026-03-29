import Foundation

enum DictationPostProcessor {
    static func format(_ text: String, autoPunctuation: Bool, punctuationStyle: CleanupPunctuationStyle) -> String {
        var result = normalizeWhitespace(in: text)
        result = normalizeMixedLanguageSpacing(in: result)
        result = normalizePreferredPunctuationCharacters(in: result, punctuationStyle: punctuationStyle)
        guard autoPunctuation else {
            return cleanupSpacingAroundPunctuation(in: result, punctuationStyle: punctuationStyle)
        }

        result = normalizeListPunctuation(in: result, punctuationStyle: punctuationStyle)
        result = addQuestionBreaks(in: result, punctuationStyle: punctuationStyle)
        result = addSentenceBreaks(in: result, punctuationStyle: punctuationStyle)
        result = addClauseCommas(in: result, punctuationStyle: punctuationStyle)
        result = addTerminalPunctuation(in: result, punctuationStyle: punctuationStyle)
        result = cleanupSpacingAroundPunctuation(in: result, punctuationStyle: punctuationStyle)
        return result
    }

    private static func normalizeWhitespace(in text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeMixedLanguageSpacing(in text: String) -> String {
        text
            .replacingOccurrences(of: "(\\p{Han})\\s+([A-Za-z0-9])", with: "$1$2", options: .regularExpression)
            .replacingOccurrences(of: "([A-Za-z0-9])\\s+(\\p{Han})", with: "$1$2", options: .regularExpression)
    }

    private static func normalizePreferredPunctuationCharacters(in text: String, punctuationStyle: CleanupPunctuationStyle) -> String {
        guard punctuationStyle == .english else {
            return text
        }

        return text
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "。", with: ".")
            .replacingOccurrences(of: "？", with: "?")
            .replacingOccurrences(of: "！", with: "!")
            .replacingOccurrences(of: "、", with: ",")
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "；", with: ";")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
    }

    private static func normalizeListPunctuation(in text: String, punctuationStyle: CleanupPunctuationStyle) -> String {
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            if character == "," || character == "、" {
                let previousCharacter = previousNonWhitespaceCharacter(before: index, in: text)
                let nextIndex = text.index(after: index)
                let nextCharacter = nextNonWhitespaceCharacter(from: nextIndex, in: text)

                if let previousCharacter, nextCharacter != nil {
                    switch punctuationMark(for: .comma, previousCharacter: previousCharacter, punctuationStyle: punctuationStyle) {
                    case "，":
                        result.append("、")
                    default:
                        result.append(", ")
                    }
                } else {
                    result.append(",")
                }
            } else {
                result.append(character)
            }

            index = text.index(after: index)
        }

        return result
    }

    private static func addQuestionBreaks(in text: String, punctuationStyle: CleanupPunctuationStyle) -> String {
        var result = text
        let patterns: [(String, String)] = [
            (
                "([吗呢么呀])(?=(如果|我想|怎么|为什么|能不能|可不可以|要不要|是否|还有|那|另外))",
                punctuationStyle == .english ? "$1? " : "$1？"
            ),
            ("(\\b(?:why|how|what|when|where|who|can|could|would|should|do|does|did|is|are|will)\\b[^.?!。！？]*)(?=\\b(?:if|then|also|and)\\b)", "$1? "),
        ]

        for (pattern, template) in patterns {
            result = result.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }

        return result
    }

    private static func addSentenceBreaks(in text: String, punctuationStyle: CleanupPunctuationStyle) -> String {
        struct BoundaryRule {
            let trigger: String
            let kind: BoundaryKind
            let minimumDistance: Int
        }

        let rules = [
            BoundaryRule(trigger: "你可以", kind: .sentence, minimumDistance: 6),
            BoundaryRule(trigger: "你能", kind: .sentence, minimumDistance: 6),
            BoundaryRule(trigger: "我们还", kind: .sentence, minimumDistance: 14),
            BoundaryRule(trigger: "我还", kind: .sentence, minimumDistance: 14),
            BoundaryRule(trigger: "另外", kind: .sentence, minimumDistance: 14),
            BoundaryRule(trigger: "最后", kind: .sentence, minimumDistance: 14),
            BoundaryRule(trigger: "同时", kind: .comma, minimumDistance: 8),
            BoundaryRule(trigger: "比如", kind: .comma, minimumDistance: 8),
            BoundaryRule(trigger: "还有", kind: .comma, minimumDistance: 10),
            BoundaryRule(trigger: "我们", kind: .comma, minimumDistance: 12),
            BoundaryRule(trigger: "它们", kind: .comma, minimumDistance: 10),
        ]

        var result = text

        for rule in rules {
            var searchRange = result.startIndex..<result.endIndex

            while let foundRange = result.range(of: rule.trigger, options: [], range: searchRange) {
                let triggerStart = foundRange.lowerBound
                if triggerStart == result.startIndex {
                    searchRange = foundRange.upperBound..<result.endIndex
                    continue
                }

                guard let previousCharacter = previousNonWhitespaceCharacter(before: triggerStart, in: result) else {
                    searchRange = foundRange.upperBound..<result.endIndex
                    continue
                }

                if "，。！？,.!?、".contains(previousCharacter) {
                    searchRange = foundRange.upperBound..<result.endIndex
                    continue
                }

                let precedingText = String(result[..<triggerStart])
                let distanceSinceLastBoundary = switch rule.kind {
                case .sentence:
                    precedingText.distanceToLastStrongBoundary
                case .comma:
                    precedingText.distanceToLastBoundary
                }
                if distanceSinceLastBoundary < rule.minimumDistance {
                    searchRange = foundRange.upperBound..<result.endIndex
                    continue
                }

                let mark = punctuationMark(for: rule.kind, previousCharacter: previousCharacter, punctuationStyle: punctuationStyle)
                result.insert(contentsOf: mark, at: triggerStart)
                let nextStart = result.index(triggerStart, offsetBy: mark.count + rule.trigger.count, limitedBy: result.endIndex) ?? result.endIndex
                searchRange = nextStart..<result.endIndex
            }
        }

        return addEnglishEntitySentenceBreaks(in: result, punctuationStyle: punctuationStyle)
    }

    private static func addEnglishEntitySentenceBreaks(in text: String, punctuationStyle: CleanupPunctuationStyle) -> String {
        let predicatePattern = "(非常|很|也|最|真|特别|喜欢|觉得|说|想|看|去|是|会|正在|开始|继续|需要)"
        let pattern = "([A-Z][A-Za-z]*(?: [A-Z][A-Za-z]*){0,2})(?=\(predicatePattern))"

        var result = text
        var searchRange = result.startIndex..<result.endIndex

        while let foundRange = result.range(of: pattern, options: .regularExpression, range: searchRange) {
            let triggerStart = foundRange.lowerBound
            guard triggerStart > result.startIndex,
                  let previousCharacter = previousNonWhitespaceCharacter(before: triggerStart, in: result) else {
                searchRange = foundRange.upperBound..<result.endIndex
                continue
            }

            if "，。！？,.!?、".contains(previousCharacter) {
                searchRange = foundRange.upperBound..<result.endIndex
                continue
            }

            let precedingText = String(result[..<triggerStart])
            guard precedingText.distanceToLastStrongBoundary >= 14 else {
                searchRange = foundRange.upperBound..<result.endIndex
                continue
            }

            let mark = punctuationMark(for: .sentence, previousCharacter: previousCharacter, punctuationStyle: punctuationStyle)
            result.insert(contentsOf: mark, at: triggerStart)
            let nextStart = result.index(triggerStart, offsetBy: mark.count + result.distance(from: foundRange.lowerBound, to: foundRange.upperBound), limitedBy: result.endIndex) ?? result.endIndex
            searchRange = nextStart..<result.endIndex
        }

        return result
    }

    private static func addClauseCommas(in text: String, punctuationStyle: CleanupPunctuationStyle) -> String {
        var result = text
        let chineseConnectors = ["因为", "所以", "但是", "不过", "然后", "而且", "如果", "其实", "另外", "同时", "比如"]
        let chineseConnectorPrefix = punctuationStyle == .english ? ", " : "，"

        for connector in chineseConnectors {
            let pattern = "(?<!^)(?<![，。！？,.!?、\\s])\(NSRegularExpression.escapedPattern(for: connector))"
            result = result.replacingOccurrences(
                of: pattern,
                with: "\(chineseConnectorPrefix)\(connector)",
                options: .regularExpression
            )
        }

        result = result.replacingOccurrences(
            of: "(?<![,，.。!?！？、])\\s+(because|but|however|so|then)\\b",
            with: ", $1",
            options: [.regularExpression, .caseInsensitive]
        )

        return result
    }

    private static func addTerminalPunctuation(in text: String, punctuationStyle: CleanupPunctuationStyle) -> String {
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

        if punctuationStyle == .english {
            if looksLikeQuestion {
                return text + "?"
            }

            return text + "."
        }

        let terminalStyle = terminalPunctuationStyle(for: text)

        if looksLikeQuestion {
            return text + (terminalStyle == .cjk ? "？" : "?")
        }

        if containsChinese, terminalStyle == .cjk {
            return text + "。"
        }

        return text + "."
    }

    private static func cleanupSpacingAroundPunctuation(in text: String, punctuationStyle: CleanupPunctuationStyle) -> String {
        let normalized = text
            .replacingOccurrences(of: "\\s+([，。！？、,.!?])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "([，。！？、])\\s+", with: "$1", options: .regularExpression)

        if punctuationStyle == .english {
            return normalized
                .replacingOccurrences(of: "\\s+([,.?!:;])", with: "$1", options: .regularExpression)
                .replacingOccurrences(of: "(?<!\\d)([.,])\\s*(?=[A-Za-z\\p{Han}])", with: "$1 ", options: .regularExpression)
                .replacingOccurrences(of: "([?!:;])\\s*(?=[A-Za-z0-9\\p{Han}])", with: "$1 ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return normalized
            .replacingOccurrences(of: "([,.?!])(?=[A-Za-z\\p{Han}])", with: "$1 ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum ScriptPunctuationStyle {
    case cjk
    case latin
}

private enum BoundaryKind {
    case sentence
    case comma
}

private extension String {
    var distanceToLastBoundary: Int {
        guard let range = range(of: "[，。！？,.!?]", options: .regularExpression.union(.backwards)) else {
            return count
        }

        return distance(from: range.upperBound, to: endIndex)
    }

    var distanceToLastStrongBoundary: Int {
        guard let range = range(of: "[。！？.!?]", options: .regularExpression.union(.backwards)) else {
            return count
        }

        return distance(from: range.upperBound, to: endIndex)
    }
}

private func scriptPunctuationStyle(for character: Character) -> ScriptPunctuationStyle? {
    if character.unicodeScalars.contains(where: { $0.properties.isIdeographic }) {
        return .cjk
    }

    if character.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) {
        return .latin
    }

    return nil
}

private func terminalPunctuationStyle(for text: String) -> ScriptPunctuationStyle {
    var index = text.endIndex
    while index > text.startIndex {
        index = text.index(before: index)
        let character = text[index]
        if character.isWhitespace || "，。！？、,.!?".contains(character) {
            continue
        }

        return scriptPunctuationStyle(for: character) ?? .latin
    }

    return .latin
}

private func punctuationMark(
    for kind: BoundaryKind,
    previousCharacter: Character,
    punctuationStyle: CleanupPunctuationStyle
) -> String {
    if punctuationStyle == .english {
        switch kind {
        case .sentence:
            return ". "
        case .comma:
            return ", "
        }
    }

    switch (kind, scriptPunctuationStyle(for: previousCharacter) ?? .latin) {
    case (.sentence, .cjk):
        return "。"
    case (.sentence, .latin):
        return ". "
    case (.comma, .cjk):
        return "，"
    case (.comma, .latin):
        return ", "
    }
}

private func previousNonWhitespaceCharacter(before index: String.Index, in text: String) -> Character? {
    var cursor = index
    while cursor > text.startIndex {
        cursor = text.index(before: cursor)
        let character = text[cursor]
        if !character.isWhitespace {
            return character
        }
    }

    return nil
}

private func nextNonWhitespaceCharacter(from index: String.Index, in text: String) -> Character? {
    var cursor = index
    while cursor < text.endIndex {
        let character = text[cursor]
        if !character.isWhitespace {
            return character
        }
        cursor = text.index(after: cursor)
    }

    return nil
}

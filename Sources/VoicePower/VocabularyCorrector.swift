import Foundation

struct VocabularyCorrector: Sendable {
    private let config: VocabularyConfig

    init(config: VocabularyConfig?) {
        self.config = (config ?? .defaultConfig).withDefaults()
    }

    func correct(_ text: String) -> String {
        guard config.enabled, !config.entries.isEmpty else {
            return text
        }

        var result = text
        for replacement in compiledReplacements {
            result = result.replacingOccurrences(
                of: replacement.pattern,
                with: replacement.target,
                options: replacement.options
            )
        }
        return result
    }

    private var compiledReplacements: [CompiledReplacement] {
        config.entries
            .flatMap { entry in
                entry.resolvedAliases.map { alias in
                    CompiledReplacement(
                        pattern: Self.pattern(for: alias, matchWholeWords: entry.matchWholeWords),
                        target: entry.resolvedTarget,
                        options: entry.resolvedCaseSensitive
                            ? [.regularExpression]
                            : [.regularExpression, .caseInsensitive],
                        priority: alias.count
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.pattern.count > rhs.pattern.count
                }
                return lhs.priority > rhs.priority
            }
    }

    private static func pattern(for alias: String, matchWholeWords: Bool?) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: alias)
            .replacingOccurrences(of: "\\ ", with: "\\\\s+")

        let useWholeWords = matchWholeWords ?? alias.containsLatinWordCharactersOnly
        guard useWholeWords else {
            return escaped
        }

        return "(?<![A-Za-z0-9])\(escaped)(?![A-Za-z0-9])"
    }
}

private struct CompiledReplacement {
    let pattern: String
    let target: String
    let options: NSString.CompareOptions
    let priority: Int
}

private extension String {
    var containsLatinWordCharactersOnly: Bool {
        range(of: "^[A-Za-z0-9][A-Za-z0-9 '\\-]*$", options: .regularExpression) != nil
    }
}

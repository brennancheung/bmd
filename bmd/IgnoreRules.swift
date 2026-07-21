import Foundation

struct MarkdownScanConfiguration: Equatable {
    static let `default` = MarkdownScanConfiguration(
        customPatterns: ["node_modules"],
        usesGitIgnoreFiles: true
    )

    let customPatterns: [String]
    let usesGitIgnoreFiles: Bool

    init(customPatterns: [String], usesGitIgnoreFiles: Bool) {
        var seen = Set<String>()
        self.customPatterns = customPatterns.compactMap { pattern in
            let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
        self.usesGitIgnoreFiles = usesGitIgnoreFiles
    }
}

struct PathIgnoreRules {
    private let customRules: [PathIgnoreRule]
    private let gitIgnoreRules: [PathIgnoreRule]

    init(configuration: MarkdownScanConfiguration) {
        customRules = configuration.customPatterns.compactMap {
            PathIgnoreRule(
                pattern: $0,
                baseDirectory: "",
                allowsNegation: false,
                caseInsensitive: true
            )
        }
        gitIgnoreRules = []
    }

    private init(
        customRules: [PathIgnoreRule],
        gitIgnoreRules: [PathIgnoreRule]
    ) {
        self.customRules = customRules
        self.gitIgnoreRules = gitIgnoreRules
    }

    func addingGitIgnore(_ contents: String, in relativeDirectory: String) -> Self {
        let localRules = contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line in
                PathIgnoreRule(
                    gitIgnoreLine: String(line),
                    baseDirectory: relativeDirectory
                )
            }
        guard !localRules.isEmpty else { return self }
        return Self(
            customRules: customRules,
            gitIgnoreRules: gitIgnoreRules + localRules
        )
    }

    func ignores(_ relativePath: String, isDirectory: Bool) -> Bool {
        if customRules.contains(where: {
            $0.matches(relativePath, isDirectory: isDirectory)
        }) {
            return true
        }

        guard let lastMatchingRule = gitIgnoreRules.reversed().first(where: {
            $0.matches(relativePath, isDirectory: isDirectory)
        }) else {
            return false
        }
        return !lastMatchingRule.isNegated
    }
}

private struct PathIgnoreRule {
    let isNegated: Bool
    private let directoryOnly: Bool
    private let expression: NSRegularExpression

    init?(
        pattern rawPattern: String,
        baseDirectory: String,
        allowsNegation: Bool,
        caseInsensitive: Bool
    ) {
        guard let parsed = Self.parse(
            rawPattern,
            allowsNegation: allowsNegation
        ) else {
            return nil
        }
        isNegated = parsed.isNegated
        directoryOnly = parsed.directoryOnly
        guard let expression = try? NSRegularExpression(
            pattern: Self.expressionSource(
                for: parsed.pattern,
                baseDirectory: baseDirectory
            ),
            options: caseInsensitive ? [.caseInsensitive] : []
        ) else {
            return nil
        }
        self.expression = expression
    }

    init?(gitIgnoreLine: String, baseDirectory: String) {
        self.init(
            pattern: gitIgnoreLine,
            baseDirectory: baseDirectory,
            allowsNegation: true,
            caseInsensitive: false
        )
    }

    func matches(_ relativePath: String, isDirectory: Bool) -> Bool {
        guard !directoryOnly || isDirectory else { return false }
        let range = NSRange(relativePath.startIndex..., in: relativePath)
        return expression.firstMatch(in: relativePath, range: range) != nil
    }

    private static func parse(
        _ rawPattern: String,
        allowsNegation: Bool
    ) -> (pattern: String, isNegated: Bool, directoryOnly: Bool)? {
        var pattern = rawPattern
        if pattern.last == "\r" {
            pattern.removeLast()
        }
        if pattern.first == "\u{feff}" {
            pattern.removeFirst()
        }
        pattern = removingUnescapedTrailingSpaces(from: pattern)
        guard !pattern.isEmpty else { return nil }

        var isNegated = false
        if allowsNegation {
            if pattern.hasPrefix("#") {
                return nil
            }
            if pattern.hasPrefix("\\#") {
                pattern.removeFirst()
            }
            if pattern.hasPrefix("!") {
                isNegated = true
                pattern.removeFirst()
            } else if pattern.hasPrefix("\\!") {
                pattern.removeFirst()
            }
        }

        guard !pattern.isEmpty else { return nil }
        let directoryOnly = pattern.hasSuffix("/") && !pattern.hasSuffix("\\/")
        if directoryOnly {
            pattern.removeLast()
        }
        guard !pattern.isEmpty else { return nil }
        return (pattern, isNegated, directoryOnly)
    }

    private static func removingUnescapedTrailingSpaces(from value: String) -> String {
        var characters = Array(value)
        while characters.last == " " {
            var backslashCount = 0
            var index = characters.count - 1
            while index > 0, characters[index - 1] == "\\" {
                backslashCount += 1
                index -= 1
            }
            if backslashCount.isMultiple(of: 2) {
                characters.removeLast()
            } else {
                characters.remove(at: characters.count - 2)
                break
            }
        }
        return String(characters)
    }

    private static func expressionSource(
        for originalPattern: String,
        baseDirectory: String
    ) -> String {
        var pattern = originalPattern
        let isRooted = pattern.hasPrefix("/")
        if isRooted {
            pattern.removeFirst()
        }

        let relativeExpression = globExpression(for: pattern)
        let escapedBase = NSRegularExpression.escapedPattern(for: baseDirectory)
        if isRooted || pattern.contains("/") {
            let basePrefix = baseDirectory.isEmpty ? "" : escapedBase + "/"
            return "^" + basePrefix + relativeExpression + "$"
        }

        let descendantPrefix = baseDirectory.isEmpty
            ? "^(?:.*/)?"
            : "^" + escapedBase + "/(?:.*/)?"
        return descendantPrefix + relativeExpression + "$"
    }

    private static func globExpression(for pattern: String) -> String {
        let characters = Array(pattern)
        var expression = ""
        var index = 0

        while index < characters.count {
            let character = characters[index]
            switch character {
            case "\\":
                if index + 1 < characters.count {
                    expression += NSRegularExpression.escapedPattern(
                        for: String(characters[index + 1])
                    )
                    index += 2
                } else {
                    expression += "\\\\"
                    index += 1
                }

            case "*":
                if index + 1 < characters.count, characters[index + 1] == "*" {
                    while index + 1 < characters.count, characters[index + 1] == "*" {
                        index += 1
                    }
                    if index + 1 < characters.count, characters[index + 1] == "/" {
                        expression += "(?:.*/)?"
                        index += 2
                    } else {
                        expression += ".*"
                        index += 1
                    }
                } else {
                    expression += "[^/]*"
                    index += 1
                }

            case "?":
                expression += "[^/]"
                index += 1

            case "[":
                if let closingIndex = characters[(index + 1)...].firstIndex(of: "]") {
                    var contents = Array(characters[(index + 1)..<closingIndex])
                    if contents.first == "!" {
                        contents[0] = "^"
                    }
                    let escapedContents = contents.map { item -> String in
                        if item == "\\" || item == "]" {
                            return "\\" + String(item)
                        }
                        return String(item)
                    }.joined()
                    expression += "[" + escapedContents + "]"
                    index = closingIndex + 1
                } else {
                    expression += "\\["
                    index += 1
                }

            default:
                expression += NSRegularExpression.escapedPattern(for: String(character))
                index += 1
            }
        }

        return expression
    }
}

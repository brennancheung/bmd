import Foundation

struct FuzzyMatchRange: Equatable, Hashable {
    let start: Int
    let length: Int
}

struct FuzzyMatch: Equatable {
    let score: Int
    let ranges: [FuzzyMatchRange]
}

enum FuzzyMatcher {
    private static let boundaryBonus = 5
    private static let consecutiveBonus = 3
    private static let firstCharacterBonus = 4
    private static let maximumGapPenalty = 5

    static func score(query: String, candidate: String) -> FuzzyMatch? {
        let queryCharacters = normalizedCharacters(query)
        let candidateCharacters = Array(candidate)
        let normalizedCandidateCharacters = normalizedCharacters(candidate)
        guard !queryCharacters.isEmpty else {
            return FuzzyMatch(score: 0, ranges: [])
        }
        guard queryCharacters.count <= candidateCharacters.count else { return nil }

        let boundaries = boundaryFlags(candidateCharacters)
        let candidateCount = candidateCharacters.count
        let impossible = Int.min / 4
        var previousScores = Array(repeating: impossible, count: candidateCount)
        var predecessors = Array(
            repeating: Array(repeating: -1, count: candidateCount),
            count: queryCharacters.count
        )

        for queryIndex in queryCharacters.indices {
            var currentScores = Array(repeating: impossible, count: candidateCount)
            let prefixBest = bestPrefixIndices(previousScores)

            for candidateIndex in candidateCharacters.indices where
                queryCharacters[queryIndex] == normalizedCandidateCharacters[candidateIndex] {
                let characterScore = 1 + (boundaries[candidateIndex] ? boundaryBonus : 0)

                if queryIndex == 0 {
                    currentScores[candidateIndex] = characterScore
                        + (candidateIndex == 0 ? firstCharacterBonus : 0)
                        - min(candidateIndex, maximumGapPenalty)
                    continue
                }

                var bestScore = impossible
                var bestPredecessor = -1

                func consider(_ predecessor: Int, bonus: Int) {
                    guard predecessor >= 0, previousScores[predecessor] != impossible else {
                        return
                    }
                    let proposed = previousScores[predecessor] + bonus
                    if proposed > bestScore
                        || (proposed == bestScore && predecessor > bestPredecessor) {
                        bestScore = proposed
                        bestPredecessor = predecessor
                    }
                }

                if candidateIndex > 0 {
                    consider(candidateIndex - 1, bonus: consecutiveBonus)
                }

                if candidateIndex > 1 {
                    let largestExactGap = min(maximumGapPenalty, candidateIndex - 1)
                    for gap in 1...largestExactGap {
                        consider(candidateIndex - gap - 1, bonus: -gap)
                    }
                }

                let cappedPrefixEnd = candidateIndex - maximumGapPenalty - 1
                if cappedPrefixEnd >= 0 {
                    consider(
                        prefixBest[cappedPrefixEnd],
                        bonus: -maximumGapPenalty
                    )
                }

                guard bestPredecessor >= 0 else { continue }
                currentScores[candidateIndex] = bestScore + characterScore
                predecessors[queryIndex][candidateIndex] = bestPredecessor
            }

            previousScores = currentScores
        }

        guard let lastIndex = bestIndex(in: previousScores),
              previousScores[lastIndex] != impossible else {
            return nil
        }

        var indices = Array(repeating: 0, count: queryCharacters.count)
        var candidateIndex = lastIndex
        for queryIndex in queryCharacters.indices.reversed() {
            indices[queryIndex] = candidateIndex
            if queryIndex > 0 {
                candidateIndex = predecessors[queryIndex][candidateIndex]
            }
        }

        return FuzzyMatch(
            score: previousScores[lastIndex],
            ranges: ranges(from: indices)
        )
    }

    private static func normalizedCharacters(_ value: String) -> [Character] {
        Array(
            value.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            ).lowercased()
        )
    }

    private static func boundaryFlags(_ characters: [Character]) -> [Bool] {
        characters.indices.map { index in
            guard index > 0 else { return true }
            let previous = characters[index - 1]
            let current = characters[index]
            if " _-/.".contains(previous) { return true }
            if previous.isLowercase && current.isUppercase { return true }
            if previous.isLetter && current.isNumber { return true }
            if previous.isNumber && current.isLetter { return true }
            return false
        }
    }

    private static func bestPrefixIndices(_ scores: [Int]) -> [Int] {
        var result = Array(repeating: -1, count: scores.count)
        var best = -1
        for index in scores.indices {
            if best < 0 || scores[index] > scores[best] {
                best = index
            }
            result[index] = best
        }
        return result
    }

    private static func bestIndex(in scores: [Int]) -> Int? {
        scores.indices.max { left, right in
            if scores[left] != scores[right] {
                return scores[left] < scores[right]
            }
            return left > right
        }
    }

    private static func ranges(from indices: [Int]) -> [FuzzyMatchRange] {
        indices.reduce(into: []) { ranges, index in
            if let last = ranges.last, index == last.start + last.length {
                ranges[ranges.count - 1] = FuzzyMatchRange(
                    start: last.start,
                    length: last.length + 1
                )
            } else {
                ranges.append(FuzzyMatchRange(start: index, length: 1))
            }
        }
    }
}

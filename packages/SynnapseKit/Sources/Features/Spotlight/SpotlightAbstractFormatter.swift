import Foundation

public enum SpotlightAbstractError: Error, Sendable, Equatable {
    /// The paper title alone is too long to fit inside the 30-word, 3-line
    /// envelope while still leaving room for ANY context. Callers should
    /// either shorten the title or render the abstract without the verbatim
    /// title constraint relaxed (a deliberate downgrade).
    case titleTooLongToFit
}

public struct FormattedAbstract: Sendable, Equatable {
    public let lines: [String]
    public let wordCount: Int
    public let containsTitle: Bool

    public init(lines: [String], wordCount: Int, containsTitle: Bool) {
        self.lines = lines
        self.wordCount = wordCount
        self.containsTitle = containsTitle
    }
}

/// Enforces the spotlight-abstract data contract (see operator memory):
///   - exactly 3 lines
///   - ~30 words total, tight band [27, 33]
///   - contains the paper title verbatim, somewhere in the text
///
/// This is a pure function. No side effects. The card view enforces the
/// visual contract; this enforces the data contract.
public enum SpotlightAbstractFormatter {

    /// Hard cap per visible line. The card layout breaks above this width.
    public static let maxCharactersPerLine: Int = 96

    /// Word-count window centered on 30.
    public static let minWords: Int = 27
    public static let maxWords: Int = 33

    public static func format(
        title: String,
        raw: String
    ) throws -> FormattedAbstract {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleWords = wordCount(trimmedTitle)

        // The title must fit AND leave at least a 6-word remainder for the
        // bracketing context. Anything tighter produces an unreadable card.
        guard titleWords + 6 <= maxWords else {
            throw SpotlightAbstractError.titleTooLongToFit
        }

        // Build the body around the verbatim title. We keep the title as a
        // single contiguous token-block so word-budget compression cannot
        // shear it.
        let bodyWords = compressContext(
            raw: raw,
            availableWords: targetWords - titleWords
        )

        // Compose: lead-in (up to ~5 words from the raw context) + title +
        // tail. The verbatim title sits in the middle when context allows; it
        // anchors the abstract.
        let leadCount = min(5, max(0, (bodyWords.count - 4)))
        let lead = Array(bodyWords.prefix(leadCount))
        let tail = Array(bodyWords.dropFirst(leadCount))

        var assembled: [String] = []
        assembled.append(contentsOf: lead)
        assembled.append("___TITLE___") // sentinel; restored after wrapping
        assembled.append(contentsOf: tail)

        // Wrap into 3 lines greedy-by-width, treating the title sentinel as
        // an atomic block whose width is the title string. This guarantees we
        // never split the verbatim title across a line boundary.
        let lines = wrapToThreeLines(words: assembled, titleText: trimmedTitle)
        let joined = lines.joined(separator: " ")
        let finalWordCount = wordCount(joined)

        // Defensive: confirm post-conditions before handing back.
        precondition(lines.count == 3, "formatter should always emit 3 lines")
        let hasTitle = joined.contains(trimmedTitle)
        precondition(hasTitle, "formatter must keep title verbatim")
        // Final band check — if compression overshot, trim the tail one word
        // at a time and re-wrap. If it undershot, this is acceptable up to
        // the minimum.
        if !(minWords...maxWords).contains(finalWordCount) {
            return try rebalanceToBand(
                title: trimmedTitle,
                lead: lead,
                tail: tail
            )
        }

        return FormattedAbstract(
            lines: lines,
            wordCount: finalWordCount,
            containsTitle: true
        )
    }

    // MARK: - Internals

    /// Target words is the midpoint of the band. Compression aims here so
    /// downstream tail-trim has slack in both directions.
    private static let targetWords: Int = 30

    private static func wordCount(_ s: String) -> Int {
        s.split { $0.isWhitespace || $0.isNewline }.count
    }

    private static func tokenize(_ s: String) -> [String] {
        s.split { $0.isWhitespace || $0.isNewline }.map(String.init)
    }

    /// Compresses raw context to fit in `availableWords`, breaking only on
    /// word boundaries. Never returns a half-token. If the raw is already
    /// shorter than the budget the full tokenization is returned as-is.
    private static func compressContext(raw: String, availableWords: Int) -> [String] {
        let words = tokenize(raw)
        guard availableWords > 0 else { return [] }
        guard words.count > availableWords else { return words }
        return Array(words.prefix(availableWords))
    }

    /// Three-line wrap that treats the title as an atomic block.
    private static func wrapToThreeLines(words: [String], titleText: String) -> [String] {
        let displayWidth: (String) -> Int = { token in
            token == "___TITLE___" ? titleText.count : token.count
        }
        let displayText: (String) -> String = { token in
            token == "___TITLE___" ? titleText : token
        }

        // Target line width: distribute evenly across three lines.
        let totalLength: Int = words.reduce(0) { acc, t in acc + displayWidth(t) + 1 }
        let perLine = max(20, min(maxCharactersPerLine, totalLength / 3 + 4))

        var lines: [[String]] = [[], [], []]
        var currentLineIdx = 0
        var currentLineLen = 0

        for tok in words {
            let width = displayWidth(tok)
            let separator = lines[currentLineIdx].isEmpty ? 0 : 1
            let candidate = currentLineLen + separator + width

            if candidate <= perLine || currentLineIdx == 2 {
                lines[currentLineIdx].append(tok)
                currentLineLen = candidate
            } else {
                currentLineIdx += 1
                lines[currentLineIdx].append(tok)
                currentLineLen = width
            }

            if currentLineLen > maxCharactersPerLine && currentLineIdx < 2 {
                currentLineIdx += 1
                currentLineLen = 0
            }
        }

        // Ensure exactly 3 lines (pad if context is short).
        while lines.count < 3 { lines.append([]) }

        return lines.prefix(3).map { lineTokens in
            lineTokens.map(displayText).joined(separator: " ")
        }
    }

    /// Trims or grows the tail one word at a time until the joined word count
    /// lands in [minWords, maxWords]. Title is always preserved verbatim.
    private static func rebalanceToBand(
        title: String,
        lead: [String],
        tail: [String]
    ) throws -> FormattedAbstract {
        var workingTail = tail
        // Try shrinking first.
        while workingTail.count > 0 {
            let assembled = lead + ["___TITLE___"] + workingTail
            let lines = wrapToThreeLines(words: assembled, titleText: title)
            let joined = lines.joined(separator: " ")
            let wc = wordCount(joined)
            if (minWords...maxWords).contains(wc) {
                return FormattedAbstract(lines: lines, wordCount: wc, containsTitle: true)
            }
            if wc > maxWords {
                workingTail.removeLast()
            } else {
                break
            }
        }
        // If we under-shot, pad with neutral filler — title still verbatim,
        // the operator's invariant honored. Filler is generic English so
        // VoiceOver still produces a coherent reading.
        var padded = lead + ["___TITLE___"] + workingTail
        let filler = ["a", "concise", "spotlight", "for", "the", "operator"]
        var idx = 0
        while wordCount(
            wrapToThreeLines(words: padded, titleText: title).joined(separator: " ")
        ) < minWords && idx < filler.count {
            padded.append(filler[idx])
            idx += 1
        }
        let lines = wrapToThreeLines(words: padded, titleText: title)
        let joined = lines.joined(separator: " ")
        return FormattedAbstract(
            lines: lines,
            wordCount: wordCount(joined),
            containsTitle: joined.contains(title)
        )
    }
}

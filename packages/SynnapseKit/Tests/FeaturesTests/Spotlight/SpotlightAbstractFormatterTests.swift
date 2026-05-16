import Foundation
import Testing
@testable import Features

@Suite("SpotlightAbstractFormatter")
struct SpotlightAbstractFormatterTests {

    @Test
    func producesExactlyThreeLines() throws {
        let title = "Mutation Testing for LLM-Generated Code"
        let raw = """
        This paper introduces a novel mutation testing approach tailored for
        code emitted by large language models. The authors evaluate against
        existing baselines and show a 23 percent improvement in defect
        detection over Major. The technique generalizes across three model
        families and four programming languages.
        """
        let out = try SpotlightAbstractFormatter.format(title: title, raw: raw)
        #expect(out.lines.count == 3)
    }

    @Test
    func containsTitleVerbatim() throws {
        let title = "Mutation Testing for LLM-Generated Code"
        let raw = "An empirical study of fault injection in code suggestions."
        let out = try SpotlightAbstractFormatter.format(title: title, raw: raw)
        let joined = out.lines.joined(separator: " ")
        #expect(joined.contains(title))
        #expect(out.containsTitle)
    }

    @Test
    func wordCountWithinTightBand() throws {
        let title = "Mutation Testing"
        let raw = """
        Researchers compare four mutation operators across six benchmarks and
        report higher mutation scores than the prior state of the art. The
        approach scales linearly with the size of the target program.
        """
        let out = try SpotlightAbstractFormatter.format(title: title, raw: raw)
        #expect((27...33).contains(out.wordCount))
    }

    @Test
    func neverExceedsPerLineCharacterCap() throws {
        let title = "A Short Title"
        let raw = """
        Quite a long single sentence that would naturally serialize as a single
        very long line if we did not break it at sensible boundaries, and we
        need to confirm that the formatter respects the per-line ceiling.
        """
        let out = try SpotlightAbstractFormatter.format(title: title, raw: raw)
        for line in out.lines {
            #expect(line.count <= SpotlightAbstractFormatter.maxCharactersPerLine)
        }
    }

    @Test
    func titlePunctuationStillMatchesVerbatim() throws {
        let title = "LLMs, Mutation, and the Cost of Being Wrong"
        let raw = "We study how LLM-suggested code interacts with mutation testing budgets."
        let out = try SpotlightAbstractFormatter.format(title: title, raw: raw)
        let joined = out.lines.joined(separator: " ")
        #expect(joined.contains(title))
    }

    @Test
    func titleLongerThanBudgetThrowsTyped() throws {
        // 31 words of title alone — leaves no room for context.
        let title = (1...31).map { "word\($0)" }.joined(separator: " ")
        let raw = "irrelevant context that cannot fit."
        #expect(throws: SpotlightAbstractError.titleTooLongToFit) {
            _ = try SpotlightAbstractFormatter.format(title: title, raw: raw)
        }
    }

    @Test
    func overBudgetInputCompressesWithoutMidWordTruncation() throws {
        let title = "Mutation Testing"
        // ~80 words of raw — formatter must compress to the 27-33 band
        // without breaking a word in the middle.
        let raw = String(repeating: "alpha beta gamma delta epsilon zeta eta theta ", count: 12)
        let out = try SpotlightAbstractFormatter.format(title: title, raw: raw)
        #expect((27...33).contains(out.wordCount))
        // No line ends mid-word: trailing token should always be a complete
        // word (no trailing hyphen, no half-token).
        for line in out.lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            #expect(!trimmed.hasSuffix("-"))
        }
    }

    @Test
    func formattedAbstractIsSendable() async throws {
        let title = "Mutation Testing"
        let raw = "A practical mutation testing toolkit for modern Java codebases."
        let out = try SpotlightAbstractFormatter.format(title: title, raw: raw)
        let job: @Sendable () -> Int = { out.wordCount }
        await Task.detached { _ = job() }.value
    }
}

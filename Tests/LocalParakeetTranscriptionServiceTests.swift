import Foundation

enum LocalParakeetTranscriptionServiceTests {
    static func run() {
        usesPredictableCPUCompute()
        parsesAndTrimsDedicatedTranscriptField()
        collapsesDecoderPunctuationRepetition()
        removesUnexpectedScriptArtifacts()
        rejectsResponsesWithoutTranscriptText()
    }

    private static func usesPredictableCPUCompute() {
        TestSupport.expect(
            LocalParakeetTranscriptionService.computeUnits == "cpu",
            "Local transcription should avoid sporadic Neural Engine cold-start stalls"
        )
    }

    private static func collapsesDecoderPunctuationRepetition() {
        let data = Data("Versie 7.. Really??? Yes!!".utf8)
        let transcript = try? LocalParakeetTranscriptionService.parseTranscript(from: data)
        TestSupport.expectEqual(transcript, "Versie 7.. Really??? Yes!")
    }

    private static func removesUnexpectedScriptArtifacts() {
        let data = Data("naïeve façade — goed. Ю".utf8)
        let transcript = try? LocalParakeetTranscriptionService.parseTranscript(from: data)
        TestSupport.expectEqual(transcript, "naïeve façade — goed.")

        let nonLatin = Data("Dit is naam Юрий".utf8)
        let preservedName = try? LocalParakeetTranscriptionService.parseTranscript(from: nonLatin)
        TestSupport.expectEqual(preservedName, "Dit is naam Юрий")

        let fullNonLatin = Data("Добрый день. Ю".utf8)
        let preservedTranscript = try? LocalParakeetTranscriptionService.parseTranscript(from: fullNonLatin)
        TestSupport.expectEqual(preservedTranscript, "Добрый день. Ю")
    }

    private static func parsesAndTrimsDedicatedTranscriptField() {
        let data = Data("  Hallo wereld. \n".utf8)
        let transcript = try? LocalParakeetTranscriptionService.parseTranscript(from: data)
        TestSupport.expectEqual(transcript, "Hallo wereld.")
    }

    private static func rejectsResponsesWithoutTranscriptText() {
        let data = Data()
        do {
            _ = try LocalParakeetTranscriptionService.parseTranscript(from: data)
            TestSupport.expect(false, "Empty helper output should fail parsing")
        } catch {
            TestSupport.expect(true, "Empty helper output correctly rejected")
        }
    }
}

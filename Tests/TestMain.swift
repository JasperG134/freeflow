import Foundation

@main
struct FreeFlowTests {
    static func main() {
        AppContextServiceTests.run()
        ModelConfigurationTests.run()
        ShortcutCoreTests.run()
        SemanticVersionTests.run()
        LLMCooldownManagerTests.run()
        LocalParakeetModelStoreTests.run()
        LocalParakeetTranscriptionServiceTests.run()
        LocalTranscriptionPolicyTests.run()
        TranscriptTextCoreTests.run()
        print("FreeFlowTests passed")
    }
}

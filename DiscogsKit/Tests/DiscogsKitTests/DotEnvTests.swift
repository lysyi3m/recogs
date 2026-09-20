import Foundation
import Testing
@testable import DevSupport

@Suite("DotEnv parsing")
struct DotEnvTests {
    @Test("Parses keys, ignores comments, strips quotes and export")
    func parse() {
        let contents = """
        # comment
        DISCOGS_PAT=abc123

        export DISCOGS_CONTACT="https://example.com"
        QUOTED='single'
        MALFORMED
        """
        let parsed = DotEnv.parse(contents)

        #expect(parsed["DISCOGS_PAT"] == "abc123")
        #expect(parsed["DISCOGS_CONTACT"] == "https://example.com")
        #expect(parsed["QUOTED"] == "single")
        #expect(parsed["MALFORMED"] == nil)
        #expect(parsed.count == 3)
    }
}

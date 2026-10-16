import Foundation

struct TestData {

    // Test words that should exist in the seed database
    static let searchTerms = [
        "apple",    // Common word with multiple definitions
        "test",     // Simple word for basic tests
        "example",  // Another reliable test word
        "word",     // Basic dictionary term
        "book"      // Common noun for testing
    ]

    // Expected partial content for verification
    static let expectedResults: [String: String] = [
        "apple": "fruit",
        "test": "procedure",
        "example": "thing",
        "word": "unit",
        "book": "written"
    ]

    // Test data for bookmark and history flows
    static let bookmarkTestWords = ["apple", "test"]
    static let historyTestWords = ["example", "word", "book"]

    /// Issue #92 — language-pair keys as rendered on the Dictionary Order
    /// screen (`DictionaryGrouping.pairKey(forSource:)`): sorted ISO-639-3
    /// codes joined by `-`. One row / toggle / drag slot per pair.
    struct Pairs {
        static let english = "eng"        // wordnet
        static let russian = "eng-rus"    // openrussian
        static let spanish = "eng-spa"    // freedict-eng-spa + wordnet-spa-eng
        static let arabic = "arb-eng"     // wordnet-arb-eng
        /// All bundled pairs (lookup set; not the on-screen order).
        static let all = [english, russian, spanish, arabic]

        /// Underlying source IDs per pair (for `source_stripe_<source>` /
        /// badge assertions, which stay per source).
        static let sources: [String: [String]] = [
            english: ["wordnet"],
            russian: ["openrussian"],
            spanish: ["freedict-eng-spa", "wordnet-spa-eng"],
            arabic: ["wordnet-arb-eng"],
        ]

        /// Issue #105 — the bundled import fixture's custom pair (not in `all`).
        static let importFixture = "custom:test_import_fixture"
    }

    /// Issue #91 — bundled source IDs used by the info-detail ids.
    struct Sources {
        static let wordnet = "wordnet"
        static let openrussian = "openrussian"
        static let wordnetSpaEng = "wordnet-spa-eng"
        static let freedictEngSpa = "freedict-eng-spa"
        static let wordnetArbEng = "wordnet-arb-eng"
        /// Issue #105 — source ID of `test_import_fixture.{json,sqlite}`.
        static let importFixture = "test_import_fixture"
    }

    // Timeout values for different operations
    struct Timeouts {
        static let short: TimeInterval = 2.0
        static let medium: TimeInterval = 5.0
        static let long: TimeInterval = 10.0
    }
}

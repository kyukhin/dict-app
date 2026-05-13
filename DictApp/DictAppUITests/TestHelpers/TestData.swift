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

    // Timeout values for different operations
    struct Timeouts {
        static let short: TimeInterval = 2.0
        static let medium: TimeInterval = 5.0
        static let long: TimeInterval = 10.0
    }
}
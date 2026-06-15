// AppConstants.swift
// App-wide constants that aren't derived at runtime.

import Foundation

enum AppConstants {
    /// App Store numeric ID — used to build the "Write a review" deep link (#81).
    static let appStoreID = "6763217128"

    /// Deep link to the App Store "write a review" page (#81). Optional rather
    /// than force-unwrapped so a malformed string can never crash Settings at
    /// render time (the caller conditionally renders the row).
    static var writeReviewURL: URL? {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }
}

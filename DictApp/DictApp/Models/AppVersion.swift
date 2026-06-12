// AppVersion.swift
// Single source of truth for the running app's version string.
//
// The displayed version is the build-time `git describe` of HEAD, injected
// into the bundle's Info.plist as the custom `GIT_DESCRIBE` key (Issue #39):
//   Config/BuildInfo.xcconfig (written by Scripts/generate_build_info.sh as a
//   scheme Build pre-action) -> GIT_DESCRIBE build setting -> Info.plist
//   $(GIT_DESCRIBE) substitution -> bundle -> here.
//
// A clean build (HEAD exactly on a tag) carries the bare tag, e.g. "v1.3.0";
// a dev build carries the full describe, e.g. "v1.2.0-8-gc7238e0". The script
// chose the right string per case, so `displayString` returns it near-verbatim
// (only stripping a leading "v" for the App Store / iOS Settings convention).
//
// Pure value type — no UIKit, no SwiftUI, no `@MainActor`. Constant for the
// lifetime of the process: `AppVersion.current` is computed once and reused.

import Foundation

/// Immutable view of the app's version: the git-describe string the build was
/// stamped with, plus the marketing version and build number from the plist.
struct AppVersion {
    /// Process-wide singleton. Computed once on first access.
    static let current = AppVersion()

    /// Raw `git describe` string captured at build time from the bundle's
    /// `GIT_DESCRIBE` Info.plist key. Empty only if the substitution chain
    /// is misconfigured (the build's validation phase fails loud before that
    /// can ship) — `displayString` then falls back to `marketingVersion`.
    let gitDescribe: String

    /// Marketing version, e.g. `"1.2.0"` (`CFBundleShortVersionString`).
    /// `"unknown"` if the Info.plist entry is missing — a visible-failure
    /// default rather than a fake `"1.0"`. Kept for `verboseString` and as
    /// the `displayString` fallback.
    let marketingVersion: String

    /// Build number, e.g. `"3"` (`CFBundleVersion`). `"0"` if missing. Kept
    /// for bug-report triage (`verboseString`).
    let buildNumber: String

    /// Build an `AppVersion` from a `Bundle` (default `.main`), reading
    /// `GIT_DESCRIBE` + the standard `CFBundle*` keys from its Info.plist.
    init(bundle: Bundle = .main) {
        self.init(infoDictionary: bundle.infoDictionary)
    }

    /// Bypasses `Bundle` entirely — used by unit tests to exercise the
    /// missing/malformed-Info.plist paths without subclassing `Bundle`
    /// (which iOS caches by path and resists overriding).
    init(infoDictionary: [String: Any]?) {
        self.gitDescribe = infoDictionary?["GIT_DESCRIBE"] as? String ?? ""
        self.marketingVersion = infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        self.buildNumber = infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// Test seam (Issue #39): construct directly from a synthetic
    /// `git describe` string with no git and no bundle. The script's
    /// exact-match-vs-always choice can't be unit-tested in Swift, so the
    /// seam covers the deterministic half — classification + display — for
    /// each describe shape (clean tag, post-tag dev, no-tags SHA).
    init(describeOutput: String,
         marketingVersion: String = "unknown",
         buildNumber: String = "0") {
        self.gitDescribe = describeOutput
        self.marketingVersion = marketingVersion
        self.buildNumber = buildNumber
    }

    /// What Settings displays. Returns the `git describe` string with a single
    /// leading `v` stripped (e.g. `v1.3.0` → `1.3.0`,
    /// `v1.2.0-8-gc7238e0` → `1.2.0-8-gc7238e0`), matching the App Store /
    /// iOS Settings convention. Falls back to `marketingVersion` only if
    /// `gitDescribe` is empty (defensive — the build fails loudly first).
    var displayString: String {
        guard !gitDescribe.isEmpty else { return marketingVersion }
        // Only strip a leading "v" when it precedes a digit — i.e. version-shaped
        // tags like "v1.3.0" become "1.3.0", but a hypothetical non-version tag
        // like "v_unstable" stays intact.
        if gitDescribe.hasPrefix("v"),
           let next = gitDescribe.dropFirst().first,
           next.isNumber {
            return String(gitDescribe.dropFirst())
        }
        return gitDescribe
    }

    /// True when HEAD was exactly on a semantic-version tag at build time —
    /// a bare `vX.Y.Z` / `X.Y.Z` with no `-<N>-g<sha>` dev suffix and not a
    /// bare commit SHA. The optional leading `v` is tolerated.
    var isCleanTag: Bool {
        gitDescribe.range(
            of: #"^v?\d+\.\d+\.\d+$"#,
            options: .regularExpression
        ) != nil
    }

    /// What bug-report telemetry displays. Always includes the build number
    /// so triage can match a report to a specific archive, e.g.
    /// `"1.2.0-8-gc7238e0 (build 3)"`.
    var verboseString: String {
        "\(displayString) (build \(buildNumber))"
    }
}

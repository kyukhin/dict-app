// AppVersion.swift
// Single source of truth for the running app's version string.
//
// Reads `CFBundleShortVersionString` and `CFBundleVersion` from the
// generated Info.plist (populated at build time from
// `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode
// project) and derives a release channel from runtime signals.
//
// Pure value type — no UIKit, no SwiftUI, no `@MainActor`. Constant
// for the lifetime of the process: `AppVersion.current` is computed
// once and reused.

import Foundation

/// What kind of build is currently running. Detected at runtime so the
/// developer never has to flip a flag before archiving.
enum ReleaseChannel {
    /// `#if DEBUG` is set — Xcode → Run on device/simulator.
    case debug
    /// Release config running with a sandbox-receipt — TestFlight
    /// (or Release-config simulator, rare).
    case testFlight
    /// Release config with an embedded provisioning profile — Ad-Hoc,
    /// Enterprise, or Developer-export distribution.
    case development
    /// Release config, no sandbox receipt, no embedded profile —
    /// genuine App Store-distributed binary.
    case appStore

    /// Anything except `.appStore` displays with the `-unreleased`
    /// suffix.
    var isUnreleased: Bool { self != .appStore }
}

/// Immutable view of the app's version, build number, and release
/// channel. Both Settings and `SupportService` read from this single
/// type so they never disagree on what the running build is.
struct AppVersion {
    /// Process-wide singleton. Computed once on first access.
    static let current = AppVersion()

    /// Marketing version, e.g. `"1.1.0"`. `"unknown"` if the Info.plist
    /// entry is missing (shouldn't happen with `GENERATE_INFOPLIST_FILE`
    /// — visible-failure default rather than a fake `"1.0"`).
    let marketingVersion: String

    /// Build number, e.g. `"2"`. `"0"` if the Info.plist entry is
    /// missing.
    let buildNumber: String

    /// The kind of binary this process is — derived from layered
    /// runtime signals (`#if DEBUG`, receipt path, embedded profile).
    let channel: ReleaseChannel

    init(bundle: Bundle = .main, channel: ReleaseChannel? = nil) {
        self.init(
            infoDictionary: bundle.infoDictionary,
            channel: channel ?? Self.detectChannel(bundle: bundle)
        )
    }

    /// Internal initializer that bypasses `Bundle` entirely. Used by
    /// unit tests to exercise the missing/malformed-Info.plist paths
    /// without having to subclass `Bundle` (which iOS caches by path
    /// and resists overriding).
    init(infoDictionary: [String: Any]?, channel: ReleaseChannel) {
        self.marketingVersion = infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        self.buildNumber = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        self.channel = channel
    }

    /// What Settings displays: `"1.1.0-unreleased"` for any non-App-Store
    /// build, `"1.1.0"` for an App Store-distributed binary.
    var displayString: String {
        channel.isUnreleased ? "\(marketingVersion)-unreleased" : marketingVersion
    }

    /// What bug-report telemetry displays. Always includes the build
    /// number so triage can match a report to a specific archive.
    /// e.g. `"1.1.0-unreleased (build 2)"`.
    var verboseString: String {
        "\(displayString) (build \(buildNumber))"
    }

    // MARK: - Channel detection

    /// Internal so tests can exercise the resolution rules with a
    /// controlled `Bundle`. Production callers go through `current`.
    static func detectChannel(bundle: Bundle = .main) -> ReleaseChannel {
        #if DEBUG
        return .debug
        #else
        // TestFlight & the Release-config simulator both report
        // `sandboxReceipt` for the receipt filename. App Store ships
        // a file literally named `receipt`.
        if bundle.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            return .testFlight
        }
        // Ad-Hoc / Enterprise / Developer-export builds carry an
        // embedded provisioning profile. App Store strips this file.
        if bundle.url(forResource: "embedded", withExtension: "mobileprovision") != nil {
            return .development
        }
        return .appStore
        #endif
    }
}

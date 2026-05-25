// SupportService.swift
// Builds the email artifacts for the in-app "Report a Bug" flow.
//
// Pure: no UI, no side effects beyond reading
// `Bundle.main.infoDictionary`, `UIDevice.current`, `utsname`, and
// `LocalizationManager.shared`. The view layer composes the result
// into either an `MFMailComposeViewController` sheet or a `mailto:`
// URL fallback.

import Foundation
import MessageUI
import UIKit

@MainActor
final class SupportService {
    static let shared = SupportService()

    /// Single source of truth for the destination address. Change this in
    /// one place if the inbox moves.
    let recipient: String = "support@libredict.app"

    // MARK: - Composition

    /// Localized subject line, with a machine-readable build prefix so
    /// inbox triage can sort and filter by version.
    /// e.g. `[LibreDict 1.1.0 b2] LibreDict bug report`
    func subject() -> String {
        let prefix = "[LibreDict \(appVersion) b\(buildNumber)]"
        let localizedSubject = LocalizationManager.shared.localized("support.email.subject")
        return "\(prefix) \(localizedSubject)"
    }

    /// Greeting (localized) + blank lines for the user's prose +
    /// telemetry block (English, delimited).
    func bodyTemplate() -> String {
        let greeting = LocalizationManager.shared.localized("support.email.bodyGreeting")
        return greeting + "\n\n\n" + telemetryBlock()
    }

    /// Plain-text, ASCII-safe footer with app/device/locale identifiers.
    /// Kept in English regardless of UI language: humans triage these
    /// reports, and the block is structured technical data, not prose.
    func telemetryBlock() -> String {
        let language = LocalizationManager.shared.currentLanguage.code
        let systemLocale = Locale.current.identifier
        return """
        ---
        LibreDict \(appVersion) (build \(buildNumber))
        iOS \(UIDevice.current.systemVersion)
        Device: \(deviceModelIdentifier)
        UI language: \(language)
        System locale: \(systemLocale)
        ---
        """
    }

    // MARK: - Capability

    /// `true` when the device has a configured Mail account and
    /// `MFMailComposeViewController` can present a draft.
    var canSendMail: Bool {
        MFMailComposeViewController.canSendMail()
    }

    /// `mailto:` fallback URL used when `canSendMail` is false. iOS routes
    /// this to a third-party mail client if one is registered. Returns
    /// `nil` only if URL encoding fails (shouldn't happen with valid
    /// inputs — defensive).
    func mailtoURL() -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject()),
            URLQueryItem(name: "body", value: bodyTemplate()),
        ]
        return components.url
    }

    // MARK: - Sources

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    /// Hardware model identifier (e.g. `"iPhone16,2"`).
    /// `UIDevice.current.model` returns the generic `"iPhone"` and is
    /// useless for triage; we read `utsname.machine` instead, which is the
    /// same string Apple's Feedback Assistant captures.
    private var deviceModelIdentifier: String {
        #if targetEnvironment(simulator)
        if let identifier = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(identifier) (Simulator)"
        }
        #endif
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { partial, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            partial.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? "unknown" : identifier
    }
}

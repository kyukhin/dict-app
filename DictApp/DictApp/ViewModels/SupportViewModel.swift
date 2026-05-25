// SupportViewModel.swift
// Presentation state for the "Report a Bug" flow on the Settings screen.
//
// Three-tier fallback:
//   1. `MFMailComposeViewController.canSendMail()` → present compose sheet
//   2. else `openURL(mailto:)` → third-party mail client (Gmail/Outlook/…)
//   3. else surface an alert offering to copy the support address

import Foundation
import SwiftUI
import MessageUI

@MainActor
final class SupportViewModel: ObservableObject {
    /// Drives the `.sheet` modifier hosting `MailComposeView`. Set to
    /// `true` only when `MFMailComposeViewController.canSendMail()` is
    /// true and the user taps Report a Bug.
    @Published var isPresentingMail: Bool = false

    /// Non-nil when the three-tier fallback has reached its final stage
    /// (no Mail account, no third-party client). Drives the `.alert`
    /// modifier that offers to copy the recipient address.
    @Published var mailUnavailableAlert: MailUnavailableReason?

    /// Reasons the mail flow can fail before the compose sheet appears.
    /// Backed by `String` so each case is its own stable `Identifiable` id
    /// and SwiftUI's `.alert(item:)` can drive presentation directly.
    enum MailUnavailableReason: String, Identifiable {
        /// Neither Apple Mail nor a third-party `mailto:` handler is
        /// installed; the user can only copy the address.
        case noMailClient

        /// Stable identity for `.alert(item:)` presentation.
        var id: String { rawValue }

        /// Catalog key for the alert body text shown to the user.
        var localizedBodyKey: LocalizedStringKey {
            switch self {
            case .noMailClient: "support.mailUnavailable.body.noClient"
            }
        }
    }

    /// Entry point invoked by the Report a Bug button. Runs the
    /// three-tier fallback: native compose sheet → `mailto:` URL →
    /// copy-address alert. The `openURL` action is injected from the
    /// view's `@Environment(\.openURL)` so this view-model stays
    /// testable without UIKit.
    func startReportFlow(openURL: OpenURLAction) {
        if SupportService.shared.canSendMail {
            isPresentingMail = true
            return
        }

        guard let url = SupportService.shared.mailtoURL() else {
            mailUnavailableAlert = .noMailClient
            return
        }

        openURL(url) { [weak self] accepted in
            guard let self else { return }
            if !accepted {
                self.mailUnavailableAlert = .noMailClient
            }
        }
    }

    /// Informational callback from `MFMailComposeViewControllerDelegate`.
    /// We don't persist sent/cancelled outcomes; the system already gives
    /// the user feedback (sent animation, etc.).
    func handleMailDidFinish(_ result: MFMailComposeResult, error: Error?) {
        isPresentingMail = false
    }
}

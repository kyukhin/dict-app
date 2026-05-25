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
    @Published var isPresentingMail: Bool = false
    @Published var mailUnavailableAlert: MailUnavailableReason?

    enum MailUnavailableReason: String, Identifiable {
        case noMailClient

        var id: String { rawValue }

        var localizedBodyKey: LocalizedStringKey {
            switch self {
            case .noMailClient: "support.mailUnavailable.body.noClient"
            }
        }
    }

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

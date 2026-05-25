// MailComposeView.swift
// SwiftUI wrapper around UIKit's MFMailComposeViewController.
// There is no SwiftUI-native mail compose API — this is the standard
// `UIViewControllerRepresentable` bridge.

import SwiftUI
import MessageUI

/// SwiftUI bridge around `MFMailComposeViewController`. Use inside a
/// `.sheet(isPresented:)` modifier; the wrapper owns the UIKit
/// controller's lifetime and forwards the delegate callback to
/// `onFinish`.
struct MailComposeView: UIViewControllerRepresentable {
    /// Address pre-filled in the To: field.
    let recipient: String
    /// Pre-filled subject line.
    let subject: String
    /// Pre-filled plain-text body.
    let body: String
    /// Called when the compose VC finishes (sent / cancelled / saved /
    /// failed). The coordinator dismisses the sheet before invoking.
    let onFinish: (MFMailComposeResult, Error?) -> Void

    /// Builds the underlying `MFMailComposeViewController` with the
    /// pre-fill values and wires it to the coordinator.
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    /// No-op: the compose VC owns its own state once presented.
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    /// Builds a coordinator that captures `onFinish` for the delegate
    /// callback.
    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    /// Owns the `MFMailComposeViewControllerDelegate` conformance and
    /// forwards the `didFinishWith` callback to the SwiftUI layer after
    /// dismissing the controller.
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        /// Captured at coordinator construction; called once on finish.
        let onFinish: (MFMailComposeResult, Error?) -> Void

        /// Stores the SwiftUI completion handler for delegate forwarding.
        init(onFinish: @escaping (MFMailComposeResult, Error?) -> Void) {
            self.onFinish = onFinish
        }

        /// MessageUI doesn't dismiss the controller automatically — we
        /// dismiss, then forward the result to the SwiftUI layer.
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            controller.dismiss(animated: true) { [onFinish] in
                onFinish(result, error)
            }
        }
    }
}

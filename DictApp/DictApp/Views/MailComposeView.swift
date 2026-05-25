// MailComposeView.swift
// SwiftUI wrapper around UIKit's MFMailComposeViewController.
// There is no SwiftUI-native mail compose API — this is the standard
// `UIViewControllerRepresentable` bridge.

import SwiftUI
import MessageUI

struct MailComposeView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let onFinish: (MFMailComposeResult, Error?) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {
        // No-op: the compose VC owns its own state once presented.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult, Error?) -> Void

        init(onFinish: @escaping (MFMailComposeResult, Error?) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            // MessageUI doesn't dismiss the controller automatically.
            controller.dismiss(animated: true) { [onFinish] in
                onFinish(result, error)
            }
        }
    }
}

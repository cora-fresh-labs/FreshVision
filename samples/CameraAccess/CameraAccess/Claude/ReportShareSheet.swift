import SwiftUI
import UIKit

/// UIActivityViewController wrapper for sharing report content.
struct ReportShareSheet: UIViewControllerRepresentable {
  let items: [Any]

  init(text: String) {
    self.items = [text]
  }

  init(items: [Any]) {
    self.items = items
  }

  func makeUIViewController(context: Context) -> UIActivityViewController {
    let activityViewController = UIActivityViewController(
      activityItems: items,
      applicationActivities: nil
    )

    activityViewController.excludedActivityTypes = [
      .assignToContact,
      .addToReadingList,
    ]

    return activityViewController
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

import SwiftUI
import UIKit

struct VideoDownloadFileExportRequest: Identifiable {
    let id = UUID()
    let url: URL
}

struct VideoDownloadFileExporter: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context)
        -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(
            forExporting: [url],
            asCopy: true
        )
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}
}

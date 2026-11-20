import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct PickedAudio {
    let directory: URL
    let files: [URL]
    let failures: [String]
}

struct AudioImportPicker: UIViewControllerRepresentable {
    var selected: (PickedAudio) -> Void
    var cancelled: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Some audio codecs are advertised as generic data by Files providers.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ picker: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: AudioImportPicker
        init(parent: AudioImportPicker) { self.parent = parent }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.cancelled()
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            let fm = FileManager.default
            let batch = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            var files: [URL] = []
            var failures: [String] = []
            // Retain the sandbox copies before dismissing the picker. Each gets
            // its own directory so different providers can return the same name.
            for (index, url) in urls.enumerated() {
                let folder = batch.appendingPathComponent(String(index), isDirectory: true)
                let local = folder.appendingPathComponent(url.lastPathComponent)
                do {
                    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                    try fm.copyItem(at: url, to: local)
                    files.append(local)
                } catch { failures.append("\(url.lastPathComponent) — \(error.localizedDescription)") }
            }
            if urls.isEmpty { failures.append("Files returned an empty selection. Please choose a file again.") }
            parent.selected(PickedAudio(directory: batch, files: files, failures: failures))
        }
    }
}

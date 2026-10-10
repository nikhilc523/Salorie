import SwiftUI
import UIKit
import Vision

/// Captures a Nutrition Facts panel with a **single-shot** camera (one photo, with an
/// optional crop), OCRs it with the modern Vision `RecognizeTextRequest`, and returns
/// the parsed values to prefill the manual-entry form. A plain single capture — no
/// multi-page "Save (n)" flow. Device-only (needs a camera); no-op on the Simulator.
struct LabelScannerView: UIViewControllerRepresentable {
    /// Fired once OCR + (optional) on-device AI have produced a scan. The producer is
    /// swapped (regex → AI) but the terminal type is still a `ParsedLabel` inside
    /// `LabelScan`; the consumer never branches.
    var onResult: (LabelScan) -> Void
    var onDismiss: () -> Void
    /// Called the instant a photo is captured (before OCR/AI finish) so the form can
    /// show the "reading label" card while the model refines.
    var onScanStarted: () -> Void = {}

    static var isSupported: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = true          // let the user pinch-crop to the label → sharper OCR
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult, onDismiss: onDismiss, onScanStarted: onScanStarted)
    }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onResult: (LabelScan) -> Void
        let onDismiss: () -> Void
        let onScanStarted: () -> Void
        init(onResult: @escaping (LabelScan) -> Void, onDismiss: @escaping () -> Void,
             onScanStarted: @escaping () -> Void) {
            self.onResult = onResult; self.onDismiss = onDismiss; self.onScanStarted = onScanStarted
        }

        // Delegate is not main-actor-isolated → keep methods `nonisolated`, extract the
        // photo as Sendable `Data` synchronously, then hop to the main actor for UI.
        nonisolated func imagePickerController(_ picker: UIImagePickerController,
                                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // Prefer the cropped image; fall back to the full frame.
            let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            let data: Data? = image?.pngData()
            Task { @MainActor in
                onDismiss()
                guard let data else { return }
                onScanStarted()
                let lines = await Coordinator.recognizeText(data)
                // Producer swap: regex → (regex + on-device LLM refinement).
                let result = await LabelExtractor.scan(ocrLines: lines)
                onResult(result)
            }
        }
        nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            Task { @MainActor in onDismiss() }
        }

        /// Off-main OCR with the modern Vision API (accurate, for a still image).
        nonisolated static func recognizeText(_ imageData: Data) async -> [String] {
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
            guard let observations = try? await request.perform(on: imageData) else { return [] }
            return observations.compactMap { $0.topCandidates(1).first?.string }
        }
    }
}

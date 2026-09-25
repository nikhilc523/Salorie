import SwiftUI
import VisionKit
import Vision

/// Captures a Nutrition Facts panel with the document camera, OCRs it with the
/// modern Vision `RecognizeTextRequest`, and returns the parsed values to prefill
/// the manual-entry form. Device-only (needs a camera); no-op on the Simulator.
struct LabelScannerView: UIViewControllerRepresentable {
    var onResult: (ParsedLabel) -> Void
    var onDismiss: () -> Void

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult, onDismiss: onDismiss) }

    @MainActor
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onResult: (ParsedLabel) -> Void
        let onDismiss: () -> Void
        init(onResult: @escaping (ParsedLabel) -> Void, onDismiss: @escaping () -> Void) {
            self.onResult = onResult; self.onDismiss = onDismiss
        }

        // Delegate is not main-actor-isolated → keep methods `nonisolated`, hop to
        // the main actor for UI, and pass the page as Sendable `Data` into OCR.
        nonisolated func documentCameraViewController(_ c: VNDocumentCameraViewController,
                                                      didFinishWith scan: VNDocumentCameraScan) {
            let data: Data? = scan.pageCount > 0 ? scan.imageOfPage(at: 0).pngData() : nil
            Task { @MainActor in
                onDismiss()
                guard let data else { return }
                let lines = await Coordinator.recognizeText(data)
                onResult(NutritionLabelParser.parse(lines))
            }
        }
        nonisolated func documentCameraViewControllerDidCancel(_ c: VNDocumentCameraViewController) {
            Task { @MainActor in onDismiss() }
        }
        nonisolated func documentCameraViewController(_ c: VNDocumentCameraViewController, didFailWithError error: Error) {
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

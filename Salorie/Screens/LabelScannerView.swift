import SwiftUI
import VisionKit
import Vision

/// Captures a Nutrition Facts panel with the document camera, OCRs it with the
/// modern Vision `RecognizeTextRequest`, and returns the parsed values to prefill
/// the manual-entry form. Device-only (needs a camera); no-op on the Simulator.
struct LabelScannerView: UIViewControllerRepresentable {
    /// Fired once OCR + (optional) on-device AI have produced a scan. The producer is
    /// swapped (regex → AI) but the terminal type is still a `ParsedLabel` inside
    /// `LabelScan`; the consumer never branches.
    var onResult: (LabelScan) -> Void
    var onDismiss: () -> Void
    /// Called the instant a page is captured (before OCR/AI finish) so the form can
    /// show a spinner while the model refines.
    var onScanStarted: () -> Void = {}

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult, onDismiss: onDismiss, onScanStarted: onScanStarted)
    }

    @MainActor
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onResult: (LabelScan) -> Void
        let onDismiss: () -> Void
        let onScanStarted: () -> Void
        init(onResult: @escaping (LabelScan) -> Void, onDismiss: @escaping () -> Void,
             onScanStarted: @escaping () -> Void) {
            self.onResult = onResult; self.onDismiss = onDismiss; self.onScanStarted = onScanStarted
        }

        // Delegate is not main-actor-isolated → keep methods `nonisolated`, hop to
        // the main actor for UI, and pass the page as Sendable `Data` into OCR.
        nonisolated func documentCameraViewController(_ c: VNDocumentCameraViewController,
                                                      didFinishWith scan: VNDocumentCameraScan) {
            let data: Data? = scan.pageCount > 0 ? scan.imageOfPage(at: 0).pngData() : nil
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

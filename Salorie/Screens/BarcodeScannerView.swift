import SwiftUI
import VisionKit

/// Live barcode scanner (VisionKit `DataScannerViewController`) wrapped for SwiftUI.
/// Embeds the camera feed; reports the first recognised barcode payload once.
struct BarcodeScannerView: UIViewControllerRepresentable {
    /// While false the camera is paused (recognition stopped) — e.g. a result sheet is up.
    var isActive: Bool = true
    var onScan: (String) -> Void

    /// A12+ device with camera access granted.
    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.code128, .ean13, .ean8, .upce, .qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.apply(isActive: isActive, to: controller)
    }

    /// Release the camera when the scanner leaves the hierarchy (sheet dismissed), so it
    /// never keeps running in the background behind the food detail or the Add screen.
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var handled = false
        private var scanning = false
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        /// Start/stop the camera to match `isActive`, idempotently. Re-arms the one-shot
        /// `handled` guard each time scanning resumes, so returning from a result can scan again.
        func apply(isActive: Bool, to controller: DataScannerViewController) {
            if isActive {
                guard !scanning else { return }
                handled = false
                try? controller.startScanning()
                scanning = true
            } else {
                guard scanning else { return }
                controller.stopScanning()
                scanning = false
            }
        }

        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(addedItems)
        }
        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle([item])
        }

        private func handle(_ items: [RecognizedItem]) {
            guard !handled else { return }
            for item in items {
                if case let .barcode(code) = item, let payload = code.payloadStringValue, !payload.isEmpty {
                    handled = true
                    onScan(payload)
                    break
                }
            }
        }
    }
}

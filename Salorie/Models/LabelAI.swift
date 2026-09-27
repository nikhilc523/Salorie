import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Availability gate for the on-device Foundation Models LLM used to refine OCR'd
/// nutrition labels. Everything is optional: the model needs iOS 26 + an
/// Apple-Intelligence-eligible device + Apple Intelligence enabled + the model
/// downloaded. Everything else must fall back to the regex parser, so `isAvailable`
/// is the single guard every call site checks (re-checked per call — availability
/// can change at runtime as the model downloads or the user toggles the setting).
///
/// `import FoundationModels` only exists on the iOS 26 SDK, so all use is wrapped in
/// `#if canImport(FoundationModels)` + `#available(iOS 26, *)` — lower deployment
/// targets still compile, and the app degrades to today's OCR behaviour.
enum LabelAI {
    /// True only when the on-device model is ready to answer right now.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *) else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
        #else
        return false
        #endif
    }

    /// A short, user-facing reason the model can't be used — shown as a hint under the
    /// scan control so the user knows why they're getting the "basic scan". `nil` when
    /// the model is available (or the SDK/OS predates Foundation Models).
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *) else { return nil }
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device can't run on-device AI."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence to auto-fill."
        case .unavailable(.modelNotReady):
            return "AI model still downloading — using basic scan."
        case .unavailable:
            return "Using basic scan."
        @unknown default:
            return "Using basic scan."
        }
        #else
        return nil
        #endif
    }
}

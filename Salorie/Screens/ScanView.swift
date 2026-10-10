import SwiftUI
import AVFoundation
import VisionKit

/// Barcode / label scanner. Live camera in a warm viewfinder with an animated
/// corner-bracket reticle and sweeping scan line. On a recognised barcode it
/// looks up the matching food and opens the food detail. Includes a "Simulate
/// Scan" shortcut and manual entry so it also works on the Simulator.
struct ScanView: View {
    @Environment(MockStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    @State private var sweep = false
    @State private var breathe = false
    @State private var cameraAuthorized = false
    @State private var selectedFood: Food?      // resolved food shown over the live camera
    @State private var loggedFromScan = false   // set when the detail actually logs the food
    @State private var flash = false
    @State private var showManualEntry = false
    @State private var manualCode = ""
    @State private var notFoundCode: String?
    @State private var torchOn = false
    @State private var showManualFood = false
    @State private var pendingCode = ""   // barcode being added by hand
    @State private var looking = false   // network lookup (OFF/USDA) in flight
    @FocusState private var manualFieldFocused: Bool

    private let scanTint = RingColor.calories.tint  // oatmeal — the calorie-ring colour (the app accent for scan flows)

    var body: some View {
        ZStack {
            // Full-bleed live camera (or a graceful dark fallback with no camera).
            cameraLayer
                .ignoresSafeArea()

            // Framing guide + prompt, centered over the feed (Apple code-scanner style).
            VStack(spacing: 18) {
                reticle
                guidance
            }
            .offset(y: -24)

            // Floating glass chrome: close ✕ + flashlight on top, manual entry at the bottom.
            VStack {
                topBar
                Spacer()
                manualEntryButton
                    .padding(.bottom, 28)
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 4)

            if looking { lookingOverlay }

            // Scanned code isn't in any database → custom glass card (not a system alert,
            // whose buttons ignore our tint and render in the global terracotta accent).
            if notFoundCode != nil { noMatchOverlay }
        }
        .background(Color.black)
        .tint(scanTint)                 // calorie-ring accent for scan chrome
        .statusBarHidden()
        .onDisappear { setTorch(false) }
        .sheet(item: $selectedFood, onDismiss: finishScanResult) { food in
            FoodDetailView(food: food, onLogged: { loggedFromScan = true })
        }
        .sheet(isPresented: $showManualFood) {
            ManualFoodEntryView(prefillBarcode: pendingCode)
        }
        // Camera can't read the barcode → type the number in and look it up.
        // Custom liquid-glass sheet (not a system alert) so it matches the scanner.
        .sheet(isPresented: $showManualEntry, onDismiss: { manualCode = "" }) {
            manualCodeSheet
        }
        .onAppear(perform: start)
    }

    // MARK: Camera layer

    @ViewBuilder private var cameraLayer: some View {
        if cameraAuthorized && BarcodeScannerView.isSupported {
            // Pause recognition while the food detail is up; it resumes on cancel.
            BarcodeScannerView(isActive: selectedFood == nil, onScan: handleScan)
                .overlay(scrim)
        } else {
            cameraPlaceholder
        }
    }

    // MARK: Floating glass chrome

    private var topBar: some View {
        HStack {
            glassCircleButton("xmark") {          // close — user changed their mind
                HapticManager.shared.trigger(.light)
                dismiss()
            }
            Spacer()
            glassCircleButton(torchOn ? "bolt.fill" : "bolt.slash.fill",
                              tint: torchOn ? scanTint : .white) {
                HapticManager.shared.trigger(.light)
                setTorch(!torchOn)
            }
        }
    }

    /// The scanner's one floating control shape — reused for both the close ✕ and the
    /// flashlight, so every overlay button reads as the same liquid-glass circle.
    private func glassCircleButton(_ system: String, tint: Color = .white,
                                   action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .glassEffect(.regular.interactive(), in: Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }

    private var manualEntryButton: some View {
        Button {
            HapticManager.shared.trigger(.light)
            showManualEntry = true
        } label: {
            Label("Enter code manually", systemImage: "keyboard")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(scanTint)     // oatmeal — matches the scanner accent
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Manual barcode entry — a clean liquid-glass sheet (replaces the system alert)

    private var manualCodeSheet: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(scanTint)
                Text("Enter barcode")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Type the number printed under the barcode and we'll look it up.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }

            TextField("e.g. 883572133501", text: $manualCode)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .tint(scanTint)
                .focused($manualFieldFocused)
                .submitLabel(.search)
                .onSubmit(lookUpManualCode)
                .padding(.horizontal, 18)
                .padding(.vertical, 15)
                .glassEffect(.regular, in: Capsule())
                .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: 1))

            HStack(spacing: 12) {
                Button {
                    HapticManager.shared.trigger(.light)
                    showManualEntry = false
                } label: {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.plain)

                Button(action: lookUpManualCode) {
                    let isEmpty = manualCode.trimmingCharacters(in: .whitespaces).isEmpty
                    Text("Look up")
                        .font(.system(size: 16, weight: .bold))
                        // No solid fill — a glossy liquid-glass capsule with calorie-ring
                        // text, matching the Cancel button's glass treatment.
                        .foregroundStyle(scanTint)
                        .opacity(isEmpty ? 0.4 : 1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(manualCode.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.bg)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.bg)
        .onAppear { manualFieldFocused = true }
    }

    /// Trim, dismiss the sheet, then resolve the typed code through the normal path.
    private func lookUpManualCode() {
        let code = manualCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        manualCode = ""
        showManualEntry = false
        handleScan(code)
    }

    /// Shown while resolving a barcode via the live OFF/USDA fallback.
    private var lookingOverlay: some View {
        HStack(spacing: 9) {
            ProgressView().tint(scanTint)
            Text("Looking up…")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .glassEffect(.regular, in: Capsule())
        .transition(.opacity)
    }

    /// "No match for that code" — a centered liquid-glass card over a dim scrim, with
    /// the calorie-ring accent on the primary action (matches the scanner's language).
    private var noMatchOverlay: some View {
        let code = notFoundCode ?? ""
        return ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { withAnimation(.snappy(duration: 0.2)) { notFoundCode = nil } }

            VStack(spacing: 18) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(scanTint)
                VStack(spacing: 8) {
                    Text("No match for that code")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("\(code) isn't in the catalog or Open Food Facts. Add it by hand — you can scan its nutrition label.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 12) {
                    Button {
                        HapticManager.shared.trigger(.light)
                        withAnimation(.snappy(duration: 0.2)) { notFoundCode = nil }
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        HapticManager.shared.trigger(.light)
                        pendingCode = code
                        notFoundCode = nil
                        showManualFood = true
                    } label: {
                        Text("Add Manually")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(scanTint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.surface))
            .padding(.horizontal, 32)
        }
        .transition(.opacity)
    }

    /// Toggle the capture device torch (no-op on Simulator / devices without one).
    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            torchOn = on
        } catch { }
    }

    /// Top + bottom darkening so the white glass controls and prompt stay legible
    /// over any camera image. Non-interactive so taps pass through to the scanner.
    private var scrim: some View {
        LinearGradient(colors: [.black.opacity(0.45), .clear, .clear, .black.opacity(0.55)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    /// Shown when there's no camera (Simulator / permission denied). The manual-entry
    /// button below still lets the user type a barcode and look it up.
    private var cameraPlaceholder: some View {
        ZStack {
            Color.black
            VStack(spacing: 12) {
                Image(systemName: "camera.metering.center.weighted")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
                Text("Camera unavailable")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text("Enter the barcode by hand instead.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var reticle: some View {
        let w: CGFloat = 246, h: CGFloat = 150
        return ZStack {
            CornerBrackets(cornerLength: 26, radius: 16)
                .stroke(
                    LinearGradient(colors: [RingColor.calories.base, scanTint],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: w, height: h)
                .shadow(color: scanTint.opacity(0.55), radius: 12)
                .scaleEffect(breathe ? 1.03 : 1.0)
                .opacity(flash ? 1 : 0.95)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(LinearGradient(colors: [.clear, scanTint, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: w - 22, height: 2.5)
                .shadow(color: scanTint.opacity(0.8), radius: 6)
                .offset(y: sweep ? (h / 2 - 14) : -(h / 2 - 14))
                .opacity(flash ? 0 : 1)

            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(scanTint.opacity(0.9))
                .scaleEffect(flash ? 1.25 : 1)
                .opacity(flash ? 1 : 0)
        }
    }

    // MARK: Guidance

    private var guidance: some View {
        VStack(spacing: 6) {
            Text("Point at a barcode")
                .font(.sectionTitle)
                .foregroundStyle(.white)
            Text("We'll match it against USDA, Open Food Facts, and your items.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
    }

    // MARK: Lifecycle & scan handling

    private func start() {
        if !reduceMotion {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { sweep = true }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { breathe = true }
        }
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            await MainActor.run { cameraAuthorized = granted }
        }
        // Screenshot/testing hook: auto-fire a scan.
        if ProcessInfo.processInfo.environment["SALORIE_MANUAL"] == "1" {
            pendingCode = "0000000000000"; showManualFood = true
        }
        if ProcessInfo.processInfo.environment["SALORIE_ENTERCODE"] == "1" {
            showManualEntry = true   // open the glass "Enter barcode" sheet
        }
        if ProcessInfo.processInfo.environment["SALORIE_SCAN_HIT"] == "1" {
            // Default resolves in the bundled catalog; SALORIE_SCAN_CODE overrides
            // (e.g. a barcode only the live OFF/USDA fallback can resolve).
            handleScan(ProcessInfo.processInfo.environment["SALORIE_SCAN_CODE"] ?? "883572133501")
        }
    }

    private func handleScan(_ payload: String) {
        let code = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !looking else { return }
        Task {
            looking = true
            defer { looking = false }
            if let food = await store.food(forBarcode: code) {
                HapticManager.shared.trigger(.success)
                setTorch(false)
                withAnimation(.snappy(duration: 0.18)) { flash = true }
                try? await Task.sleep(for: .milliseconds(220))
                withAnimation(.snappy) { flash = false }
                // Show the detail over the (now paused) camera. On cancel we stay here to
                // scan again; on a real log we leave the scanner (see `finishScanResult`).
                selectedFood = food
            } else {
                HapticManager.shared.trigger(.warning)
                notFoundCode = code
            }
        }
    }

    /// Runs after the food detail closes. If the user actually logged the food, the task
    /// is done → dismiss the whole scanner back to Add. Otherwise stay on the scanner
    /// (the camera resumes automatically once `selectedFood` is nil).
    private func finishScanResult() {
        if loggedFromScan {
            loggedFromScan = false
            dismiss()
        }
    }
}

// MARK: - Corner-bracket reticle shape

/// Four rounded L-shaped corners (viewfinder brackets).
struct CornerBrackets: Shape {
    var cornerLength: CGFloat = 26
    var radius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = radius, c = cornerLength

        // Top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + r + c))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + r + c, y: rect.minY))
        // Top-right
        p.move(to: CGPoint(x: rect.maxX - r - c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r + c))
        // Bottom-right
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - r - c))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - r - c, y: rect.maxY))
        // Bottom-left
        p.move(to: CGPoint(x: rect.minX + r + c, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r - c))
        return p
    }
}

#Preview {
    ScanView()
        .environment(MockStore())
        .preferredColorScheme(.dark)
}

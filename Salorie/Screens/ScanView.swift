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

    @State private var sweep = false
    @State private var breathe = false
    @State private var cameraAuthorized = false
    @State private var selectedFood: Food?
    @State private var flash = false
    @State private var showManualEntry = false
    @State private var manualCode = ""
    @State private var notFoundCode: String?
    @State private var torchOn = false
    @State private var showManualFood = false
    @State private var pendingCode = ""   // barcode being added by hand
    @State private var looking = false   // network lookup (OFF/USDA) in flight

    private let scanTint = RingColor.carb.tint      // warm terracotta (palette, no blue)

    var body: some View {
        VStack(spacing: 22) {
            viewfinder
            guidance
            actions
            Spacer(minLength: 0)
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .sheet(item: $selectedFood) { FoodDetailView(food: $0) }
        .sheet(isPresented: $showManualFood) {
            ManualFoodEntryView(prefillBarcode: pendingCode)
        }
        .alert("No match for that code", isPresented: .constant(notFoundCode != nil)) {
            Button("Add Manually") { pendingCode = notFoundCode ?? ""; notFoundCode = nil; showManualFood = true }
            Button("Cancel", role: .cancel) { notFoundCode = nil }
        } message: {
            Text("\(notFoundCode ?? "") isn't in the catalog or Open Food Facts. Add it by hand — you can scan its nutrition label.")
        }
        .alert("Enter barcode", isPresented: $showManualEntry) {
            TextField("Barcode number", text: $manualCode)
                .textInputAutocapitalization(.characters)
            Button("Look up") { let c = manualCode; manualCode = ""; handleScan(c) }
            Button("Cancel", role: .cancel) { manualCode = "" }
        }
        .onAppear(perform: start)
    }

    // MARK: Viewfinder — live camera + animated reticle

    private var viewfinder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))

            if cameraAuthorized && BarcodeScannerView.isSupported {
                BarcodeScannerView(onScan: handleScan)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(scrim)
                    .overlay(alignment: .topTrailing) { torchButton }
            } else {
                cameraPlaceholder
            }

            reticle
            if looking { lookingOverlay }
        }
        .frame(height: 340)
        .padding(.horizontal, Metrics.pagePadding)
        .compositingGroup()
        .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
        .onDisappear { setTorch(false) }
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

    private var torchButton: some View {
        Button {
            HapticManager.shared.trigger(.light)
            setTorch(!torchOn)
        } label: {
            Image(systemName: torchOn ? "bolt.fill" : "bolt.slash.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(torchOn ? RingColor.protein.tint : Theme.textSecondary)
                .frame(width: 40, height: 40)
                .glassEffect(.regular, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(12)
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

    /// Soft vignette so the reticle reads over a busy camera image.
    private var scrim: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(RadialGradient(colors: [.clear, .black.opacity(0.35)], center: .center, startRadius: 90, endRadius: 240))
    }

    private var cameraPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.metering.center.weighted")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
            Text("Camera unavailable")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Text("Use Simulate Scan below")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary.opacity(0.7))
        }
    }

    private var reticle: some View {
        let w: CGFloat = 246, h: CGFloat = 150
        return ZStack {
            CornerBrackets(cornerLength: 26, radius: 16)
                .stroke(
                    LinearGradient(colors: [RingColor.protein.tint, scanTint],
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
            Text("Point at a barcode or nutrition label")
                .font(.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
            Text("We'll match it against USDA, Open Food Facts, and your custom items.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: Actions (warm glass — no blue)

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                handleScan("883572133501")   // real UPC-A → GTIN-14 in the bundled catalog
            } label: {
                Label("Simulate Scan", systemImage: "barcode")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(scanTint)

            Button {
                HapticManager.shared.trigger(.light)
                showManualEntry = true
            } label: {
                Label("Enter Code", systemImage: "keyboard")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(scanTint)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, Metrics.pagePadding)
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
                selectedFood = food
            } else {
                HapticManager.shared.trigger(.warning)
                notFoundCode = code
            }
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

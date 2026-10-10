import SwiftUI

// MARK: - Geometry

/// Where the capsule sits. On Dynamic-Island devices it's drawn exactly over the
/// hardware island (~126×37, centered, top ≈ 11). On older devices (top inset
/// under 51) the same capsule grows down from under the status bar.
private struct IslandGeometry {
    let width: CGFloat        // full screen width
    let hasDynamicIsland: Bool
    let top: CGFloat          // y of the capsule's top edge, in screen coords

    init(width: CGFloat, safeTop: CGFloat) {
        self.width = width
        self.hasDynamicIsland = safeTop >= IslandMotion.dynamicIslandThreshold
        self.top = hasDynamicIsland ? IslandMotion.islandTopInset : max(safeTop, 8)
    }

    var midX: CGFloat { width / 2 }

    /// Idle island rect in screen space — the flight target.
    var idleRect: CGRect {
        CGRect(x: midX - IslandMotion.idleSize.width / 2, y: top,
               width: IslandMotion.idleSize.width, height: IslandMotion.idleSize.height)
    }
}

// MARK: - Squash keyframe value

private struct Squash: Equatable { var sx: CGFloat = 1; var sy: CGFloat = 1 }

// MARK: - IslandOverlay

/// The capsule and its content. One continuous shape morphs between sizes; content
/// is layered on top at the final fixed size and blur-replaces in/out. Mounted once
/// at the app root, above the tab bar, inside the "screen" coordinate space.
struct IslandOverlay: View {
    @Environment(IslandController.self) private var island
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Full-bleed reader: its local origin is the screen's top-left, matching the
        // "screen" space that row tiles report in, so flights and the island line up.
        // The real top inset comes from UIKit (SwiftUI's `safeAreaInsets` reports 0
        // once the reader ignores the safe area).
        GeometryReader { geo in
            let g = IslandGeometry(width: geo.size.width, safeTop: island.topInset)
            let size = currentSize(idle: IslandMotion.idleSize)

            ZStack(alignment: .top) {
                // Center horizontally with a full-width frame (NOT `.position`, whose
                // animated re-centering let the shrinking card drift sideways on close).
                // maxWidth:.infinity keeps the capsule dead-center as its width morphs,
                // so it collapses straight back into the pill. Vertical placement is a
                // plain offset from the top inset.
                capsule(size: size)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .offset(y: g.top)

                FlightLayer()
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .onAppear {
                island.reduceMotion = reduceMotion
                island.islandCenter = g.idleRect
            }
            .onChange(of: reduceMotion) { _, new in island.reduceMotion = new }
            .onChange(of: g.idleRect) { _, new in island.islandCenter = new }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        // This overlay lives in the app's TOP window, so it — not RootView — is the
        // view iOS consults for the status bar. Hide the clock/wifi/battery while the
        // island is expanded so it reads as the Dynamic Island swallowing the screen.
        .statusBarHidden(island.statusBarHidden)
        .sensoryFeedback(.impact(weight: .light), trigger: island.gulpCount)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: island.spitCount)
        .sensoryFeedback(.success, trigger: island.mealCreatedCount)
    }

    // MARK: Shape

    private func capsule(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.black)
            .frame(width: size.width, height: size.height)
            // Clip content to the SAME continuous rounded-rect as the shell, so as the
            // capsule grows the card is REVEALED by the expanding window rather than
            // fading in on top of it — this is what makes it read like the hardware
            // Dynamic Island unfurling its content instead of a card popping in.
            .overlay {
                content
                    .frame(width: size.width, height: size.height)
                    .geometryGroup()
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .compositingGroup()
            // Gulp (log/tray add) — a WHISPER of a settle, well under the expansion so
            // it never fights the morph. On the initial open the grow spring carries the
            // motion; this only adds a tiny "swallow" on rapid re-adds to an open card.
            .keyframeAnimator(initialValue: Squash(), trigger: island.gulpCount) { view, s in
                view.scaleEffect(x: s.sx, y: s.sy, anchor: .top)
            } keyframes: { _ in
                KeyframeTrack(\.sx) {
                    SpringKeyframe(1.018, duration: 0.14)
                    SpringKeyframe(1.0, duration: 0.24)
                }
                KeyframeTrack(\.sy) {
                    SpringKeyframe(1.028, duration: 0.14)
                    SpringKeyframe(1.0, duration: 0.24)
                }
            }
            .keyframeAnimator(initialValue: Squash(), trigger: island.spitCount) { view, s in
                view.scaleEffect(x: s.sx, y: s.sy, anchor: .top)
            } keyframes: { _ in
                KeyframeTrack(\.sx) {
                    SpringKeyframe(0.9, duration: 0.12)
                    SpringKeyframe(1.06, duration: 0.16)
                    SpringKeyframe(1.0, duration: 0.12)
                }
                KeyframeTrack(\.sy) {
                    SpringKeyframe(0.84, duration: 0.12)
                    SpringKeyframe(1.1, duration: 0.16)
                    SpringKeyframe(1.0, duration: 0.12)
                }
            }
            // A shadow only while expanded — at idle the pill is black-on-black over
            // the real Dynamic Island and must have no halo so it merges seamlessly.
            // The pill is ALWAYS present (never opacity 0): the card visibly grows
            // OUT of this DI-sized pill and collapses back INTO it — the island
            // "swallowing" the food — instead of a card appearing from nowhere.
            .shadow(color: .black.opacity(island.mode == .idle ? 0 : 0.35), radius: 12, y: 6)
    }

    // MARK: Content router

    @ViewBuilder
    private var content: some View {
        switch island.mode {
        case .idle:
            Color.clear
        case .logCard:
            if island.showContent {
                if reduceMotion { LogCardContent().transition(.opacity) }
                else { LogCardContent().transition(.blurReplace) }
            }
        case .tray:
            TrayContent().transition(.opacity)
        case .mealCard:
            if island.showContent {
                if reduceMotion { MealCardContent().transition(.opacity) }
                else { MealCardContent().transition(.blurReplace) }
            }
        }
    }

    // MARK: Size / corner from mode

    private func currentSize(idle: CGSize) -> CGSize {
        switch island.mode {
        case .idle: return idle
        case .logCard: return IslandMotion.logCardSize
        case .mealCard: return IslandMotion.mealCardSize
        case .tray:
            return CGSize(width: IslandMotion.trayWidth(count: island.trayItems.count),
                          height: IslandMotion.trayHeight)
        }
    }

    private var cornerRadius: CGFloat {
        switch island.mode {
        case .idle: return IslandMotion.idleCorner
        case .logCard: return IslandMotion.logCorner
        case .mealCard: return IslandMotion.mealCorner
        case .tray: return IslandMotion.trayCorner
        }
    }
}

// MARK: - Log card content

private struct LogCardContent: View {
    @Environment(IslandController.self) private var island

    var body: some View {
        HStack(spacing: 12) {
            slotTile
            VStack(alignment: .leading, spacing: 1) {
                Text(island.logSlot.rawValue.uppercased())
                    .font(.system(size: 10, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(island.logSlot.sunColor.opacity(0.9))
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(island.mealTotal, format: .number)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: Double(island.mealTotal)))
                        // A subtle scale bump each time the total increments, so the
                        // count-up reads clearly even at a glance.
                        .keyframeAnimator(initialValue: 1.0, trigger: island.numberPopCount) { view, s in
                            view.scaleEffect(s, anchor: .leading)
                        } keyframes: { _ in
                            SpringKeyframe(1.14, duration: 0.16)
                            SpringKeyframe(1.0, duration: 0.26)
                        }
                    Text("kcal")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Text(island.lastFoodName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            batchPill
            // The real home-screen rising-sun rings, minus the percentage pills —
            // same design, same oatmeal/caramel/terracotta colors.
            SalorieRings(calories: island.rings.calories,
                         protein: island.rings.protein,
                         carbs: island.rings.carbs,
                         showPills: false, showShadow: false)
                .frame(width: 54, height: 30)
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
    }

    private var slotTile: some View {
        Image(systemName: island.logSlot.symbol)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(island.logSlot.sunColor)
            .frame(width: 46, height: 46)
            .background(island.logSlot.sunColor.opacity(0.16),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var batchPill: some View {
        Text("+\(island.batchKcal)")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(island.batchKcal)))
            .foregroundStyle(Color(hex: 0x86B98E))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Color(hex: 0x86B98E).opacity(0.16), in: Capsule())
            .keyframeAnimator(initialValue: 1.0, trigger: island.popCount) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(1.25, duration: 0.16)
                SpringKeyframe(1.0, duration: 0.22)
            }
    }
}

// MARK: - Tray content (meal building)

private struct TrayContent: View {
    @Environment(IslandController.self) private var island

    /// At most 4 slots. Up to 4 items → that many icons. Beyond 4 → a `+N` overflow
    /// badge (the older items) plus the 3 most-recently-added icons. The badge count
    /// updates live; the icon count never grows past 4.
    private var items: [Food] { island.trayItems }
    private var overflow: Bool { items.count > 4 }
    private var visible: [Food] { overflow ? Array(items.suffix(3)) : items }
    private var hiddenCount: Int { items.count - 3 }   // shown in the +N badge

    var body: some View {
        // Everything lives in the card's LOWER half (pushed down by the Spacer) so
        // it clears the hardware Dynamic Island cutout sitting over the top.
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 12) {
                // LEFT — the collected items as OVERLAPPING stacked chips (+ overflow
                // badge). Leftmost sits on top so it cascades cleanly to the right.
                HStack(spacing: -9) {
                    if overflow {
                        overflowBadge
                            .zIndex(100)
                            .transition(.scale.combined(with: .opacity))
                    }
                    ForEach(Array(visible.enumerated()), id: \.element.id) { i, food in
                        icon(food)
                            .zIndex(Double(visible.count - i))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Spacer(minLength: 8)
                // RIGHT — running calories, small.
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(island.trayKcal, format: .number)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(hex: 0xE3D9C6))          // oatmeal
                        .contentTransition(.numericText(value: Double(island.trayKcal)))
                    Text("kcal")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 15)
        }
    }

    private func icon(_ food: Food) -> some View {
        Image(systemName: food.symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(food.tint.fg)
            .frame(width: 30, height: 30)
            .background(food.tint.bg, in: Circle())
            // Solid black ring so overlapping chips read as separate discs.
            .overlay(Circle().stroke(.black, lineWidth: 2))
    }

    /// The `+N` chip standing in for the older items once we pass 4.
    private var overflowBadge: some View {
        Text("+\(hiddenCount)")
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(hiddenCount)))
            .foregroundStyle(Color(hex: 0xE3D9C6))                      // oatmeal
            .frame(width: 30, height: 30)
            .background(Color(hex: 0x2E2A24), in: Circle())             // warm dark
            .overlay(Circle().stroke(Color(hex: 0xE3D9C6).opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Meal card content (created meal)

private struct MealCardContent: View {
    @Environment(IslandController.self) private var island

    var body: some View {
        // Same compact shape as the log card: icon tile · text · right accessory.
        HStack(spacing: 12) {
            Image(systemName: island.mealSymbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(island.mealTint.fg)
                .frame(width: 46, height: 46)
                .background(island.mealTint.bg,
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("NEW MEAL · \(island.logSlot.rawValue.uppercased())")
                    .font(.system(size: 10, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(island.mealTint.fg.opacity(0.9))
                Text(island.mealName)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white).lineLimit(1)
                // Overlapping ingredient chips + count — no calories.
                HStack(spacing: 6) {
                    HStack(spacing: -6) {
                        ForEach(Array(island.mealItems.enumerated()), id: \.element.id) { i, food in
                            Image(systemName: food.symbol)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(food.tint.fg)
                                .frame(width: 20, height: 20)
                                .background(food.tint.bg, in: Circle())
                                .overlay(Circle().stroke(.black, lineWidth: 1.5))
                                .zIndex(Double(island.mealItems.count - i))
                        }
                    }
                    Text("\(island.mealItems.count) items")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer(minLength: 4)
            if island.showMealCheck {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: 0x86B98E))
                    .frame(width: 34, height: 34)
                    .background(Color(hex: 0x86B98E).opacity(0.18), in: Circle())
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
    }
}

// MARK: - Previews

#Preview("Log one item") {
    IslandPreviewHarness { store, island, tile in
        island.log(SampleData.foods[0], slot: .breakfast, servings: 1, from: tile, store: store)
    }
}

#Preview("Log 3 quickly") {
    IslandPreviewHarness { store, island, tile in
        let foods = SampleData.foods
        island.log(foods[0], slot: .breakfast, servings: 1, from: tile, store: store)
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            island.log(foods[1], slot: .breakfast, servings: 1, from: tile, store: store)
            try? await Task.sleep(for: .milliseconds(700))
            island.log(foods[2], slot: .breakfast, servings: 1, from: tile, store: store)
        }
    }
}

#Preview("Build a 4-item meal") {
    IslandPreviewHarness { _, island, tile in
        let foods = SampleData.foods
        Task {
            for f in foods.prefix(4) {
                island.addToTray(f, from: tile)
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}

#Preview("Remove one item") {
    IslandPreviewHarness { _, island, tile in
        let foods = Array(SampleData.foods.prefix(3))
        Task {
            for f in foods { island.addToTray(f, from: tile); try? await Task.sleep(for: .milliseconds(450)) }
            try? await Task.sleep(for: .milliseconds(700))
            island.removeFromTray(foods[1], to: tile)
        }
    }
}

#Preview("Create the meal") {
    IslandPreviewHarness { _, island, tile in
        let foods = Array(SampleData.foods.prefix(4))
        Task {
            for f in foods { island.addToTray(f, from: tile); try? await Task.sleep(for: .milliseconds(450)) }
            try? await Task.sleep(for: .milliseconds(700))
            let kcal = foods.reduce(0) { $0 + $1.calories }
            let protein = Int(foods.reduce(0.0) { $0 + $1.protein }.rounded())
            island.createMeal(name: "Protein Bowl", symbol: "takeoutbag.and.cup.and.straw.fill",
                              tint: .green, items: foods, kcal: kcal, protein: protein)
        }
    }
}

/// Shared preview scaffold: mounts the overlay over a mock row tile and fires a
/// scenario when you tap the demo button.
private struct IslandPreviewHarness: View {
    let scenario: (MockStore, IslandController, CGRect) -> Void
    @State private var store = MockStore()
    @State private var island = IslandController()
    @State private var tile: CGRect = .zero

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: 0x0A0A0A).ignoresSafeArea()

            VStack {
                Spacer()
                Button("Run animation") {
                    island.bind(store: store)
                    scenario(store, island, tile)
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: 0xE3D9C6))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("screen")) } action: { tile = $0 }
                Spacer()
            }

            IslandOverlay()
        }
        .coordinateSpace(.named("screen"))
        .environment(store)
        .environment(island)
        .preferredColorScheme(.dark)
    }
}

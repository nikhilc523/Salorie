import SwiftUI

// MARK: - Motion constants (the single tuning surface)

/// Every timing, spring and size constant for the Dynamic-Island collect
/// animations lives here so the whole feel can be tuned in one place.
/// See `Island/README.md` for the annotated table.
enum IslandMotion {

    // MARK: Springs & curves
    /// The island shape opening wide / closing. Tuned to the hardware Dynamic
    /// Island's own fluid morph: a slightly under-damped spring so the capsule
    /// eases open with a whisper of overshoot and settles — never a hard snap.
    static let morph = Animation.spring(response: 0.5, dampingFraction: 0.8)
    /// The log card's "incoming-call" open: a springier morph that visibly
    /// overshoots then settles, so the island pops open the way an incoming call
    /// expands — more bounce than `morph` (which stays calm for the meal card/close).
    static let callOpen = Animation.spring(duration: 0.5, bounce: 0.36)
    /// Card content unfurling. A spring (not a linear smooth) so it shares the
    /// morph's fluid character and rides the expansion out of the island.
    static let content = Animation.spring(response: 0.42, dampingFraction: 0.86)
    /// Numbers rolling and rings filling.
    static let numberRoll = Animation.smooth(duration: 0.9)
    static let ringFill = Animation.smooth(duration: 0.9)
    /// Tray growing / narrowing as chips come and go.
    static let tray = Animation.spring(duration: 0.42, bounce: 0.24)
    /// The flight along the Bézier curve (row → island).
    static let flight = Animation.timingCurve(0.45, 0.05, 0.35, 1, duration: 0.65)
    /// Content folding out just before the shape closes.
    static let fadeOut = Animation.easeOut(duration: 0.16)
    /// The shape collapsing back into the idle pill on close — a clean fluid morph
    /// like Apple's Dynamic Island (continuous-corner, minimal bounce). The card
    /// content blur-replaces out (see IslandOverlay) as the container morphs.
    static let swallowClose = Animation.spring(duration: 0.4, bounce: 0.14)
    /// Reduce-Motion replacement for every shape/flight animation.
    static let reduced = Animation.smooth(duration: 0.3)

    // MARK: Durations (seconds)
    static let flightDuration: Double = 0.65
    static let autoClose: Double = 2.6          // log card
    static let mealCardHold: Double = 3.4       // created-meal card
    static let checkPopDelay: Double = 0.9      // meal card success check

    // MARK: Island geometry (points)
    // The idle pill is the hardware Dynamic Island's EXACT footprint. These values
    // are identical on every Dynamic-Island iPhone (14 Pro → 18 Pro) — a fixed
    // hardware element, not a per-device guess. Horizontal center + top come from
    // live screen geometry (see IslandOverlay), so only the pill's own size is a
    // constant, and that constant is universal.
    static let idleSize = CGSize(width: 126, height: 37.33)
    static let logCardSize = CGSize(width: 350, height: 90)
    // Same compact footprint as the log card — a meal confirmation only needs the
    // name, its items and a check, so it reuses the "item logged" shape (no calories,
    // no oversized card).
    static let mealCardSize = CGSize(width: 350, height: 90)
    /// The meal-building tray is a full card (not a thin pill) so the running kcal
    /// total sits in its LOWER half — clear of the hardware Dynamic Island cutout,
    /// which always renders on top and would otherwise hide it.
    static let trayHeight: CGFloat = 86

    static let idleCorner: CGFloat = 18.67      // continuous — half of 37.33 (a true capsule)
    static let logCorner: CGFloat = 42
    static let mealCorner: CGFloat = 42
    static let trayCorner: CGFloat = 40

    /// Tray width grows with the number of visible slots (icons + optional overflow
    /// badge), capped at 4 slots — beyond that the `+N` badge absorbs new items and
    /// the card stops widening.
    static func trayWidth(count: Int) -> CGFloat {
        let slots = min(max(count, 1), 4)
        return 190 + 26 * CGFloat(slots)     // 216 (1 item) … 294 (4+)
    }

    // MARK: Placement
    static let islandTopInset: CGFloat = 11.33  // top gap on Dynamic-Island devices
    static let dynamicIslandThreshold: CGFloat = 51  // top safe-area inset ≥ this ⇒ has DI
    static let statusBarHideWidth: CGFloat = 130     // hide status bar while wider than this

    // MARK: Gulp / spit keyframe amplitudes (see IslandOverlay)
    static let gulpDuration: Double = 0.42
    static let spitDuration: Double = 0.40

    // MARK: Metaball swallow (log flight — see MetaballFlight in FlightLayer)
    /// Blur radius for the alpha-threshold metaball fuse. Larger = a longer, gooier
    /// liquid bridge as the food blob melts into the island. Blur is applied to the
    /// black shapes, then a 0.5 alpha threshold snaps the blurred field back to hard
    /// edges — where two blobs' halos overlap, the gap fills and they read as one.
    /// Tune on-device (simctl can't show the real Dynamic Island cutout).
    static let metaballBlur: CGFloat = 9
    static let metaballThreshold: Double = 0.5
    /// The flying blob's diameter at the row → at the island (it shrinks as it melts in).
    static let metaballBlobStart: CGFloat = 46
    static let metaballBlobEnd: CGFloat = 30
    /// Fraction of the flight after which the *color* icon dissolves into the black
    /// goo (0 before, fully black by the end) — the color→black handoff.
    static let metaballFadeStart: Double = 0.5
}

// MARK: - Ring fractions

/// Simple 0…1 fractions for the island's mini rings (kept separate from the
/// app's `RingProgress`, which carries goals/consumed too).
struct IslandRings: Equatable {
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
}

// MARK: - IslandController

/// Owns all state for the custom Dynamic-Island overlay: the current mode, the
/// live flight tokens, the log-card / tray / meal-card contents, and the single
/// cancellable close timer. One continuous shape; content is layered on top.
///
/// The screens never touch the shape directly — they call `log`, `addToTray`,
/// `removeFromTray` and `createMeal`, and the controller choreographs the rest
/// through animation completions and keyframe triggers (never `asyncAfter`).
@MainActor
@Observable
final class IslandController {

    enum Mode: Equatable { case idle, logCard, tray, mealCard }

    // MARK: Observable state
    var mode: Mode = .idle
    var showContent = false          // gates card content so shape morphs first

    var flights: [Flight] = []

    // Keyframe triggers (drive squash/haptics)
    var gulpCount = 0
    var spitCount = 0
    var swallowCount = 0             // fires the "suck back into the pill" close squash
    var numberPopCount = 0          // bumps the kcal total when it increments
    var mealCreatedCount = 0

    // Log card
    var logSlot: MealSlot = .breakfast
    var mealTotal = 0                // rolls with .numericText
    var batchKcal = 0                // sum added this open session
    var batchCount = 0
    var lastFoodName = ""
    var popCount = 0                 // triggers the "+kcal" pill pop
    var rings = IslandRings()

    // Tray / meal building
    var trayItems: [Food] = []
    var trayKcal = 0

    // Meal card
    var mealName = ""
    var mealSymbol = "takeoutbag.and.cup.and.straw.fill"
    var mealTint: TagColor = .green
    var mealItems: [Food] = []
    var mealKcal = 0
    var mealProtein = 0
    var showMealCheck = false

    /// Idle island center in the "screen" coordinate space — the flight target.
    /// Written by `IslandOverlay` as geometry resolves.
    var islandCenter: CGRect = .zero

    /// The device's top safe-area inset, fed reactively from `RootView` (a UIKit
    /// window read races the first layout and can come back 0). ~59 on Dynamic-
    /// Island phones; the overlay uses it to place the capsule and pick DI vs. not.
    var topInset: CGFloat = 59

    /// Hide the status bar while the island is expanded. Stored (not computed) so
    /// SwiftUI reliably re-renders `RootView` when it flips — a computed property
    /// off `mode` didn't consistently retrigger the `.statusBarHidden` modifier.
    var statusBarHidden = false

    /// Recompute the status-bar state from the current mode/tray.
    private func refreshStatusBar() {
        switch mode {
        case .idle: statusBarHidden = false
        case .logCard, .mealCard: statusBarHidden = true
        case .tray: statusBarHidden = IslandMotion.trayWidth(count: trayItems.count) > IslandMotion.statusBarHideWidth
        }
    }

    private var closeTask: Task<Void, Never>?
    var reduceMotion = false

    // MARK: - A · Log an item

    /// Fly `food` from its row tile into the island, gulp, and open/refresh the
    /// BREAKFAST-style log card. Rapid taps keep the card open and batch up.
    func log(_ food: Food, slot: MealSlot, servings: Double, from tile: CGRect,
             store: MockStore) {
        closeTask?.cancel()
        logSlot = slot

        guard !reduceMotion else {
            store.addEntry(food, slot: slot, servings: servings)
            applyLog(food, servings: servings, slot: slot, store: store, animated: true)
            openCard(.logCard)
            announce("Logged \(food.name) to \(slot.rawValue)")
            scheduleClose(after: IslandMotion.autoClose)
            return
        }

        // Perform the store write now so totals are correct when the card rolls,
        // but hold the *displayed* roll until the token lands.
        store.addEntry(food, slot: slot, servings: servings)
        let flight = Flight(food: food, from: tile, to: islandCenter,
                            reverse: false, kind: .log(slot: slot, servings: servings))
        flights.append(flight)
        scheduleLand(flight)
        announce("Logged \(food.name) to \(slot.rawValue)")
    }

    // MARK: - B · Build a meal (tray)

    /// Fly `food` into the island tray while composing a meal.
    func addToTray(_ food: Food, from tile: CGRect) {
        closeTask?.cancel()
        guard !reduceMotion else {
            withAnimation(IslandMotion.tray) {
                if mode != .tray { mode = .tray }
                trayItems.append(food)
                trayKcal += food.calories
            }
            refreshStatusBar()
            announce("Added \(food.name)")
            return
        }
        let flight = Flight(food: food, from: tile, to: islandCenter,
                            reverse: false, kind: .tray)
        flights.append(flight)
        scheduleLand(flight)
        announce("Added \(food.name)")
    }

    /// Remove an item: spit it out of the tray and fly a token back to its row.
    func removeFromTray(_ food: Food, to tile: CGRect) {
        closeTask?.cancel()
        // Drop the chip + total immediately; the token then flies home.
        withAnimation(IslandMotion.tray) {
            if let idx = trayItems.firstIndex(where: { $0.id == food.id }) {
                trayItems.remove(at: idx)
            }
            trayKcal = max(0, trayKcal - food.calories)
        }
        refreshStatusBar()
        spitCount += 1   // squash + soft haptic

        guard !reduceMotion else {
            if trayItems.isEmpty { foldToIdle() }
            announce("Removed \(food.name)")
            return
        }
        let flight = Flight(food: food, from: islandCenter, to: tile,
                            reverse: true, kind: .remove)
        flights.append(flight)
        scheduleLand(flight)
        announce("Removed \(food.name)")
    }

    /// Turn the current tray into a finished meal card, then fold away.
    func createMeal(name: String, symbol: String, tint: TagColor,
                    items: [Food], kcal: Int, protein: Int) {
        closeTask?.cancel()
        mealName = name.isEmpty ? "New Meal" : name
        mealSymbol = symbol
        mealTint = tint
        mealItems = items
        showMealCheck = false

        let animation = reduceMotion ? IslandMotion.reduced : IslandMotion.morph
        withAnimation(animation) { mode = .mealCard }
        refreshStatusBar()
        contentTask?.cancel()
        contentTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.06))
            guard let self, !Task.isCancelled else { return }
            withAnimation(IslandMotion.content) { self.showContent = true }
            withAnimation(IslandMotion.numberRoll) {
                self.mealKcal = kcal
                self.mealProtein = protein
            }
            try? await Task.sleep(for: .seconds(IslandMotion.checkPopDelay))
            guard !Task.isCancelled else { return }
            withAnimation(self.reduceMotion ? IslandMotion.reduced
                          : .spring(duration: 0.4, bounce: 0.4)) {
                self.showMealCheck = true
            }
        }
        mealCreatedCount += 1   // .success haptic
        announce("Created meal \(mealName)")
        scheduleClose(after: IslandMotion.mealCardHold)
    }

    // MARK: - Flight completion

    /// Land the flight on a cancellable timer rather than a SwiftUI animation
    /// completion. On a busy screen (the Add tab's live search / scrolling) the
    /// `withAnimation(completion:)` callback can silently never fire, which left
    /// the card stuck closed until you switched to a calmer tab. A `Task` timer
    /// always fires, so the card opens on the screen where you tapped.
    private func scheduleLand(_ flight: Flight) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(IslandMotion.flightDuration))
            guard let self, !Task.isCancelled else { return }
            self.flightDidLand(flight)
        }
    }

    /// Called when a token reaches its target. Idempotent — guards against a
    /// double land (timer + any stray caller).
    func flightDidLand(_ flight: Flight) {
        guard flights.contains(where: { $0.id == flight.id }) else { return }
        flights.removeAll { $0.id == flight.id }

        switch flight.kind {
        case let .log(slot, servings):
            gulpCount += 1                     // squash + light haptic
            // Was the card already up? If so, roll immediately; if we're opening
            // fresh, hold the roll until the card has revealed so the count-up is
            // clearly visible as its own beat (not hidden under the open morph).
            let opening = (mode != .logCard) || !showContent
            let result = computeLog(flight.food, servings: servings, slot: slot)
            batchCount += 1
            lastFoodName = batchCount > 1
                ? "\(flight.food.name) + \(batchCount - 1) more"
                : flight.food.name
            // Show the PRIOR total instantly so the count-up starts from the right
            // number and visibly increments UP to the new total.
            mealTotal = result.total - result.added
            openCard(.logCard)
            rollTask?.cancel()
            rollTask = Task { [weak self] in
                if opening { try? await Task.sleep(for: .seconds(0.3)) }
                guard let self, !Task.isCancelled else { return }
                withAnimation(IslandMotion.numberRoll) { self.mealTotal = result.total }
                withAnimation(IslandMotion.ringFill) { self.rings = result.rings }
                self.batchKcal += result.added
                self.numberPopCount += 1                 // total scale-bump
                withAnimation(.spring(duration: 0.3, bounce: 0.4)) { self.popCount += 1 }
            }
            scheduleClose(after: IslandMotion.autoClose)

        case .tray:
            gulpCount += 1
            withAnimation(IslandMotion.tray) {
                if mode != .tray { mode = .tray }
                trayItems.append(flight.food)
                trayKcal += flight.food.calories
            }
            refreshStatusBar()

        case .remove:
            // Token has arrived home; tray already narrowed. Fold if empty.
            if trayItems.isEmpty { foldToIdle() }
        }
    }

    // MARK: - Card open / close

    private var contentTask: Task<Void, Never>?
    private var rollTask: Task<Void, Never>?

    /// Compute the slot's new total, the ring fractions and the kcal added — without
    /// mutating anything — so the land handler can stage the count-up as a clear beat.
    private func computeLog(_ food: Food, servings: Double, slot: MealSlot)
        -> (total: Int, rings: IslandRings, added: Int) {
        let added = Int((Double(food.calories) * servings).rounded())
        if let store = lastStore {
            let total = store.entries(for: slot).reduce(0) { $0 + $1.calories }
            return (total, ringFractions(from: store), added)
        }
        return (mealTotal + added, rings, added)
    }

    private func openCard(_ target: Mode) {
        let opening = mode != target
        // The log card opens with the springy "incoming-call" overshoot; Reduce
        // Motion swaps in a calm smooth.
        let animation = reduceMotion ? IslandMotion.reduced : IslandMotion.callOpen
        withAnimation(animation) { mode = target }
        refreshStatusBar()
        // Reveal content just after the shape starts morphing. Driven by a Task,
        // not a `withAnimation` completion — that callback can silently stall on a
        // busy screen (the Add tab), which would leave the shape open but empty.
        contentTask?.cancel()
        if opening {
            contentTask = Task { [weak self] in
                // A short beat — just enough for the shape to commit to growing —
                // then the content unfurls on the SAME spring, clipped by the
                // expanding capsule, so shape + card read as one fluid motion.
                try? await Task.sleep(for: .seconds(0.06))
                guard let self, !Task.isCancelled else { return }
                withAnimation(IslandMotion.content) { self.showContent = true }
            }
        } else if !showContent {
            withAnimation(IslandMotion.content) { showContent = true }
        }
    }

    /// Roll the meal total, batch the add, and refill the rings. When `store` is
    /// non-nil the totals are recomputed from it; otherwise the batch is used.
    private func applyLog(_ food: Food, servings: Double, slot: MealSlot,
                          store: MockStore?, animated: Bool) {
        let added = Int((Double(food.calories) * servings).rounded())
        batchKcal += added
        batchCount += 1
        lastFoodName = batchCount > 1
            ? "\(food.name) + \(batchCount - 1) more"
            : food.name

        let newTotal: Int
        if let store {
            newTotal = store.entries(for: slot).reduce(0) { $0 + $1.calories }
            rings = ringFractions(from: store)
        } else if let store = lastStore {
            newTotal = store.entries(for: slot).reduce(0) { $0 + $1.calories }
            rings = ringFractions(from: store)
        } else {
            newTotal = mealTotal + added
        }

        let roll = { self.mealTotal = newTotal }
        let pop = { self.popCount += 1 }
        if animated {
            withAnimation(IslandMotion.numberRoll, completionCriteria: .logicallyComplete) {
                roll()
            } completion: {}
            withAnimation(.spring(duration: 0.28, bounce: 0.35)) { pop() }
        } else {
            roll(); pop()
        }
    }

    /// Cached store so a landed flight (which carries no store) can read totals.
    private weak var lastStore: MockStore?
    func bind(store: MockStore) { lastStore = store }

    private func ringFractions(from store: MockStore) -> IslandRings {
        let t = store.targets
        func frac(_ v: Double, _ goal: Double) -> Double { goal > 0 ? v / goal : 0 }
        return IslandRings(
            calories: frac(Double(store.caloriesToday), Double(t.calories)),
            protein: frac(store.proteinToday, t.protein),
            carbs: frac(store.carbsToday, t.carbs))
    }

    // MARK: - Close

    /// Cancel any pending close and start a fresh one. The whole close sequence
    /// (content out → shape folds → reset) runs in one cancellable Task so it can
    /// never stall on a busy screen, and a new tap mid-close cancels it cleanly.
    func scheduleClose(after seconds: Double) {
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            await self?.runClose()
        }
    }

    /// Fold immediately (tray emptied / builder dismissed).
    func foldToIdle() {
        closeTask?.cancel()
        closeTask = Task { [weak self] in await self?.runClose() }
    }

    /// Content first, shape second: the ordering that reads as "calm". Task-driven
    /// so each step is guaranteed and interruption-safe.
    private func runClose() async {
        guard !Task.isCancelled else { return }
        contentTask?.cancel()
        withAnimation(reduceMotion ? IslandMotion.reduced : IslandMotion.fadeOut) {
            showContent = false
        }
        // Start collapsing the shape almost immediately so the content-fold and the
        // pill's swallow read as ONE motion (not fade, pause, then resize).
        try? await Task.sleep(for: .seconds(reduceMotion ? 0.05 : 0.1))
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? IslandMotion.reduced : IslandMotion.swallowClose) {
            mode = .idle
        }
        if !reduceMotion { swallowCount += 1 }   // pill gulps the card back in
        refreshStatusBar()
        try? await Task.sleep(for: .seconds(reduceMotion ? 0.05 : 0.5))
        guard !Task.isCancelled else { return }
        resetContent()
    }

    /// The meal builder was dismissed while still a tray (cancelled, not created):
    /// clear it so a stale tray never lingers behind a future sheet.
    func dismissTray() {
        guard mode == .tray else { return }
        flights.removeAll()
        foldToIdle()
    }

    private func resetContent() {
        guard mode == .idle else { return }
        mealTotal = 0; batchKcal = 0; batchCount = 0; lastFoodName = ""
        trayItems = []; trayKcal = 0
        mealItems = []; mealKcal = 0; mealProtein = 0; showMealCheck = false
        rings = IslandRings()
    }

    // MARK: - Accessibility

    private func announce(_ message: String) {
        var a = AttributedString(message)
        a.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(a).post()
    }
}

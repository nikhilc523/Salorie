import SwiftUI

// MARK: - Tracked-nutrient preferences

/// The nutrients a user can pin to the home screen as cards (the ring metrics —
/// calories/protein/carbs — are already the hero, so they're excluded).
extension StatKind {
    static var trackableCases: [StatKind] {
        [.fat, .fibre, .saturatedFat, .sugars, .sodium, .cholesterol]
    }
    var isTrackable: Bool { StatKind.trackableCases.contains(self) }
}

/// CSV <-> `[StatKind]` for the `@AppStorage` home preference.
enum NutrientPrefs {
    static let key = "home.trackedNutrients"
    static let `default` = "fat,fibre,sugars,sodium"

    static func list(_ raw: String) -> [StatKind] {
        raw.split(separator: ",").compactMap { StatKind(rawValue: String($0)) }.filter(\.isTrackable)
    }
    static func encode(_ kinds: [StatKind]) -> String {
        kinds.map(\.rawValue).joined(separator: ",")
    }
}

// MARK: - Weight milestone preferences

/// Present / target weight for the home milestone track. Stored as loose
/// `@AppStorage` doubles (kg) so there's no schema migration — this is a
/// lightweight testing surface, not part of the logged-data model.
///
/// `start` is captured automatically: it's the point furthest from the target
/// we've seen, so nudging the present weight toward the goal reveals the
/// milestones you've passed (and moving away resets the journey's origin).
enum WeightPrefs {
    static let startKey   = "weight.start"
    static let currentKey = "weight.current"
    static let targetKey  = "weight.target"

    /// A "nice" spacing so the track shows ~4–8 evenly placed markers that land
    /// on round numbers regardless of how big the goal is.
    static func step(forRange range: Double) -> Double {
        let candidates: [Double] = [0.5, 1, 2, 2.5, 5, 10, 20, 25, 50]
        return candidates.first { range / $0 <= 7 } ?? candidates.last!
    }

    /// Milestone weights from `start` → `target` inclusive, stepping along a nice
    /// grid, with the target always the final marker (the flag). The gap before
    /// the target may be shorter than the others — the track positions markers by
    /// value, so that reads as a slightly closer flag rather than an uneven grid.
    static func milestones(start: Double, target: Double) -> [Double] {
        guard start != target else { return [start] }
        let step = step(forRange: abs(target - start))
        let descending = target < start
        var values = [start]
        var v = start
        while true {
            v += descending ? -step : step
            if descending ? (v <= target + 0.0001) : (v >= target - 0.0001) { break }
            values.append(v)
        }
        values.append(target)
        return values
    }

    /// 0…1 progress from start toward target for the given present weight.
    static func progress(start: Double, current: Double, target: Double) -> Double {
        guard start != target else { return 0 }
        return min(max((current - start) / (target - start), 0), 1)
    }
}

// MARK: - Goal streak banner

/// One day in the week strip: its weekday letter and whether it hit the goal.
struct StreakDay: Hashable {
    let letter: String
    let onTarget: Bool
}

/// Warm, on-brand streak module: a rising-sun badge with the current streak, a
/// clear headline, and a labelled seven-day week strip so it reads at a glance.
struct StreakBanner: View {
    let streak: Int
    let week: [StreakDay]   // oldest → newest

    private let accent = Color(hex: 0xD1A67A) // caramel
    private var onTargetCount: Int { week.filter(\.onTarget).count }

    private var headline: String {
        if streak > 0 { return "\(streak)-day streak" }
        if onTargetCount > 0 { return "\(onTargetCount) of \(week.count) on target" }
        return "Start a streak"
    }
    private var subtitle: String {
        if streak > 0 { return "days hitting your calorie goal in a row" }
        if onTargetCount > 0 { return "days you hit your goal this week" }
        return "hit your calorie goal today to begin"
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0xE3D9C6), accent],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 44, height: 44)
                if streak > 0 {
                    Text("\(streak)")
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(hex: 0x17110D))
                        .contentTransition(.numericText())
                } else {
                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x17110D))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text("THIS WEEK")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Theme.textTertiary)
                HStack(spacing: 6) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        VStack(spacing: 3) {
                            Circle()
                                .fill(day.onTarget ? accent : Color(hex: 0x2A2420))
                                .frame(width: 8, height: 8)
                            Text(day.letter)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(day.onTarget ? Theme.textSecondary : Theme.textTertiary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [accent.opacity(0.12), .clear],
                                         startPoint: .leading, endPoint: .trailing))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
        )
    }
}

// MARK: - Nutrient card

extension StatKind {
    /// A sensible reference daily value so goalless nutrients still show progress.
    /// FDA %DV basis for the ones with no user goal (sugars = added-sugar limit).
    var referenceDV: Double {
        switch self {
        case .saturatedFat: 20
        case .sugars: 50
        case .cholesterol: 300
        case .sodium: 2300
        default: 0
        }
    }
    /// Compact label for the small square cards.
    var shortTitle: String {
        switch self {
        case .fat: "Fat"; case .fibre: "Fibre"; case .saturatedFat: "Sat Fat"
        case .sugars: "Sugars"; case .sodium: "Sodium"; case .cholesterol: "Chol."
        default: title
        }
    }

    /// The card's tone — drawn only from the app's three-colour sunrise palette
    /// (oatmeal · caramel · terracotta), distributed so a typical set stays varied.
    var paletteTone: Color {
        switch self {
        case .fat:          Color(hex: 0xE3D9C6) // oatmeal
        case .fibre:        Color(hex: 0xD1A67A) // caramel
        case .saturatedFat: Color(hex: 0xE3D9C6) // oatmeal
        case .sugars:       Color(hex: 0xB3664C) // terracotta
        case .sodium:       Color(hex: 0xD1A67A) // caramel
        case .cholesterol:  Color(hex: 0xB3664C) // terracotta
        default:            Color(hex: 0xD1A67A)
        }
    }
}

/// A body of water filled to `level` (0…1) with a wavy surface, for the card
/// backgrounds. `phase` slides the crests sideways so it looks like it's flowing.
private struct WaveShape: Shape {
    var level: CGFloat
    var amplitude: CGFloat
    var wavelength: CGFloat
    var phase: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let surface = rect.height * (1 - min(max(level, 0), 1))
        p.move(to: CGPoint(x: 0, y: rect.maxY))
        p.addLine(to: CGPoint(x: 0, y: surface))
        var x: CGFloat = 0
        let step: CGFloat = 3
        while x <= rect.width {
            let y = surface + sin((x / max(wavelength, 1)) * 2 * .pi + phase) * amplitude
            p.addLine(to: CGPoint(x: x, y: y))
            x += step
        }
        p.addLine(to: CGPoint(x: rect.width, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Card background: dark surface with animated floating water rising to `level`.
/// Two offset wave layers give it depth; honours Reduce Motion with a still fill.
private struct WaterFill: View {
    var level: CGFloat
    var base: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.surface
            base.opacity(0.10)   // faint glass tint so the area above the water isn't harsh black
            if reduceMotion || level <= 0 {
                GeometryReader { g in
                    ZStack(alignment: .bottom) {
                        Color.clear
                        Rectangle()
                            .fill(gradient)
                            .frame(height: g.size.height * min(max(level, 0), 1))
                    }
                }
            } else {
                TimelineView(.animation) { timeline in
                    let t = CGFloat(timeline.date.timeIntervalSinceReferenceDate)
                    ZStack {
                        WaveShape(level: level, amplitude: 3.5, wavelength: 90, phase: t * 1.6)
                            .fill(gradient)
                        WaveShape(level: level, amplitude: 2.5, wavelength: 62, phase: -t * 2.1 + 1.2)
                            .fill(base.opacity(0.18))
                    }
                }
            }
        }
    }

    private var gradient: LinearGradient {
        LinearGradient(colors: [base.opacity(0.85), base.opacity(0.28)],
                       startPoint: .bottom, endPoint: .top)
    }
}

/// The tracked-nutrient card — a square of floating water in the nutrient's tone,
/// number-forward like the hero, with a hero-style percentage pill. No arcs.
struct NutrientCard: View {
    let kind: StatKind
    let value: Double
    let goal: Double

    static let side: CGFloat = 116

    private var displayGoal: Double { goal > 0 ? goal : kind.referenceDV }
    private var fraction: Double { displayGoal > 0 ? value / displayGoal : 0 }
    private var fillFraction: Double { min(max(fraction, 0), 1) }
    private var pct: Int { Int((fraction * 100).rounded()) }
    private var over: Bool { pct >= 100 }

    private var valueText: String {
        value >= 1000
            ? value.formatted(.number.precision(.fractionLength(0)))
            : "\(Int(value.rounded()))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(kind.paletteTone).frame(width: 6, height: 6)
                Text(kind.shortTitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
            }

            Spacer(minLength: 6)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(valueText)
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(kind.unit)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
            }
            HStack(spacing: 4) {
                Text("of \(Int(displayGoal.rounded()))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
                Spacer(minLength: 2)
                pctPill
            }
            .padding(.top, 3)
        }
        .padding(12)
        .frame(width: Self.side, height: Self.side, alignment: .topLeading)
        .background(WaterFill(level: fillFraction, base: kind.paletteTone))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    /// Outline pill under goal, solid over — the same behaviour as the hero pills.
    /// White-based outline so the percent stays readable on any water tone.
    private var pctPill: some View {
        Text("\(pct)%")
            .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(over ? Color(hex: 0x17110D) : .white.opacity(0.92))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(over ? kind.paletteTone : Color.black.opacity(0.22)))
            .overlay(Capsule().stroke(over ? .clear : .white.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Settings sheet

/// Lightweight settings — currently just picks which nutrient cards appear on
/// the home screen. Backed by `@AppStorage` (no schema migration needed).
struct SettingsView: View {
    @AppStorage(NutrientPrefs.key) private var raw = NutrientPrefs.default
    @AppStorage(WeightPrefs.currentKey) private var weightCurrent = 0.0
    @AppStorage(WeightPrefs.targetKey) private var weightTarget = 0.0
    @AppStorage(WeightPrefs.startKey) private var weightStart = 0.0
    @Environment(MockStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    weightRow("Present weight", value: $weightCurrent, step: 0.1)
                    weightRow("Target weight", value: $weightTarget, step: 0.5)
                } header: {
                    Text("Weight goal")
                } footer: {
                    Text("Drives the milestone track under your rings. Set both to see the journey; nudging your present weight toward the target reveals the milestones you've passed.")
                }
                .onChange(of: weightCurrent) { _, _ in syncStart() }
                .onChange(of: weightTarget) { _, _ in syncStart() }

                Section {
                    ForEach(StatKind.trackableCases) { kind in
                        Toggle(isOn: binding(for: kind)) {
                            HStack(spacing: 10) {
                                Circle().fill(kind.numberColor).frame(width: 9, height: 9)
                                Text(kind.title)
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                        .tint(Color(hex: 0xB3664C))
                    }
                } header: {
                    Text("Home nutrient cards")
                } footer: {
                    Text("Pick extra nutrients to pin as cards on your Today screen. Calories, protein, and carbs already live in the rings.")
                }

                Section {
                    Button(role: .destructive) {
                        HapticManager.shared.trigger(.warning)
                        confirmReset = true
                    } label: {
                        Label("Delete all data", systemImage: "trash")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Erases everything you've logged — today's entries, history, trends, and your saved foods and meals — and starts the app completely empty. This can't be undone.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Delete all data?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) {
                    HapticManager.shared.trigger(.success)
                    store.resetAllData()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your logged entries, history, trends, saved foods and meals will be permanently erased. The app will start fresh and empty.")
            }
        }
    }

    /// One weight input: a typed value with a kg suffix and a fine stepper for
    /// nudging (handy for landing on values like 78.4 to test "kg away").
    private func weightRow(_ label: String, value: Binding<Double>, step: Double) -> some View {
        HStack(spacing: 10) {
            Text(label).foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            TextField("0", value: value, format: .number.precision(.fractionLength(1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 56)
                .foregroundStyle(Theme.textPrimary)
            Text("kg").foregroundStyle(Theme.textTertiary)
            Stepper("", value: value, in: 0...400, step: step)
                .labelsHidden()
        }
    }

    /// Keep `start` at the point furthest from the target we've seen, so lowering
    /// the present weight toward the goal fills the track (and raising it away
    /// re-anchors the origin). Nothing to reset — it self-calibrates.
    private func syncStart() {
        guard weightCurrent > 0, weightTarget > 0 else { return }
        if weightStart == 0 || abs(weightCurrent - weightTarget) > abs(weightStart - weightTarget) {
            weightStart = weightCurrent
        }
    }

    private func binding(for kind: StatKind) -> Binding<Bool> {
        Binding(
            get: { NutrientPrefs.list(raw).contains(kind) },
            set: { on in
                var list = NutrientPrefs.list(raw)
                if on {
                    if !list.contains(kind) { list.append(kind) }
                } else {
                    list.removeAll { $0 == kind }
                }
                raw = NutrientPrefs.encode(list)
            }
        )
    }
}

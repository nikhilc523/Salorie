import SwiftUI

/// Gradient hero card for a custom meal — same lineage as the History `BigStatCard`
/// (surface + tinted radial glow + gradient hero number + progress bar), sized
/// compact so several meals sit in a horizontal MY MEALS rail.
///
/// Tap opens the full ingredient detail; the trailing `+` quick-logs the whole meal.
struct MealHeroCard: View {
    let meal: Food
    var caloriesTarget: Int
    var onTap: () -> Void
    var onQuickAdd: () -> Void

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var grad: LinearGradient {
        LinearGradient(colors: [meal.tint.fg, meal.tint.fg.opacity(0.62)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    private var percent: Int {
        guard caloriesTarget > 0 else { return 0 }
        return Int((Double(meal.calories) / Double(caloriesTarget) * 100).rounded())
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Name + share of daily calories
                HStack(alignment: .top) {
                    Text(meal.name.uppercased())
                        .font(.system(size: 12, weight: .bold)).tracking(1.1)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    Text("\(percent)%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(grad).monospacedDigit()
                }

                Spacer(minLength: 10)

                // Hero calories
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(meal.calories)")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(grad).monospacedDigit().lineLimit(1)
                    Text("kcal")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(meal.tint.fg.opacity(0.16))
                        Capsule().fill(grad)
                            .frame(width: max(6, geo.size.width * min(Double(percent) / 100, 1) * (appeared ? 1 : 0)))
                    }
                }
                .frame(height: 6)
                .padding(.top, 10)

                // Ingredient count + macro summary
                Text("\(meal.components.count) ingredients · C\(g(meal.carbs)) P\(g(meal.protein)) F\(g(meal.fibre))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .padding(.top, 9)
            }
            .padding(18)
            .frame(width: 230, height: 160, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.surface)
                    .overlay {
                        RadialGradient(colors: [meal.tint.fg.opacity(0.20), .clear],
                                       center: .topTrailing, startRadius: 0, endRadius: 240)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
            .overlay(alignment: .bottomTrailing) { quickAddButton }
            .compositingGroup()
            .shadow(color: .black.opacity(0.35), radius: 6, y: 4)
        }
        .buttonStyle(.plain)
        .onAppear {
            guard !appeared else { return }
            if reduceMotion { appeared = true }
            else { withAnimation(.smooth(duration: 0.7)) { appeared = true } }
        }
    }

    private var quickAddButton: some View {
        Button {
            HapticManager.shared.trigger(.success)
            onQuickAdd()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 34, height: 34)
                .background(meal.tint.fg.opacity(0.22), in: Circle())
                .overlay(Circle().stroke(Theme.cardStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(12)
    }

    private func g(_ v: Double) -> String { "\(Int(v.rounded()))" }
}

/// Dashed "create" tile that sits at the end of the MY MEALS rail.
struct CreateMealCard: View {
    var action: () -> Void
    var body: some View {
        Button {
            HapticManager.shared.trigger(.light)
            action()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                Text("Create meal")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 130, height: 160)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.surface.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(Theme.divider)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tall portrait meal card (My Items grid)

/// Portrait "photo-size" meal card: colored icon tile, bold name, ingredient
/// count, and the big bold-rounded calorie number (the home-screen total style),
/// on a tinted-glow surface with a soft shadow. Built for a 2-column grid.
struct MealTallCard: View {
    let meal: Food
    var onTap: () -> Void
    var onToggleFavorite: () -> Void = {}

    private var grad: LinearGradient {
        LinearGradient(colors: [meal.tint.fg, meal.tint.fg.opacity(0.58)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: meal.symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(meal.tint.fg)
                        .frame(width: 52, height: 52)
                        .background(meal.tint.bg, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    Spacer()
                    Button {
                        HapticManager.shared.trigger(.selection)
                        onToggleFavorite()
                    } label: {
                        Image(systemName: meal.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 15))
                            .foregroundStyle(meal.isFavorite ? TagColor.yellow.fg : Theme.textTertiary)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 12)

                // Bold name
                Text(meal.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(meal.components.count) ingredients")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 3)

                Spacer(minLength: 12)

                // Big bold calorie number (home-total style), tinted
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(meal.calories)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(grad)
                        .monospacedDigit()
                        .lineLimit(1)
                    Text("kcal")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 212)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.surface)
                    .overlay {
                        RadialGradient(colors: [meal.tint.fg.opacity(0.22), .clear],
                                       center: .topTrailing, startRadius: 0, endRadius: 220)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
            .compositingGroup()
            .shadow(color: .black.opacity(0.4), radius: 9, y: 6)
            .shadow(color: meal.tint.fg.opacity(0.10), radius: 14, y: 2)
        }
        .buttonStyle(.plain)
    }
}

/// Dashed portrait "create" tile matching `MealTallCard`'s footprint.
struct CreateMealTallCard: View {
    var action: () -> Void
    var body: some View {
        Button {
            HapticManager.shared.trigger(.light)
            action()
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                Text("Create meal")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 212)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.surface.opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(Theme.divider)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview("Meal tall grid") {
    ZStack {
        Theme.bg.ignoresSafeArea()
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(SampleData.customMeals()) { MealTallCard(meal: $0, onTap: {}) }
                CreateMealTallCard(action: {})
            }
            .padding()
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Meal hero") {
    ZStack {
        Theme.bg.ignoresSafeArea()
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(SampleData.customMeals()) { meal in
                    MealHeroCard(meal: meal, caloriesTarget: 2200, onTap: {}, onQuickAdd: {})
                }
                CreateMealCard(action: {})
            }
            .padding()
        }
    }
    .preferredColorScheme(.dark)
}

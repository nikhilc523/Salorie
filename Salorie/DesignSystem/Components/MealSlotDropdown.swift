import SwiftUI

/// A custom Liquid-Glass pull-down for choosing a meal slot — our colours, our
/// motion, not the system `Menu`. A glass trigger pill drops a floating card of the
/// four meals beneath it (spring in, staggered rows, colour-coded icons, selected
/// highlight). A dim scrim catches the outside tap.
///
/// Usage:
/// ```
/// MealSlotDropdown(slot: $slot, isOpen: $slotMenuOpen)   // the trigger, placed inline
/// // …on the screen's outermost container:
/// .mealSlotMenu(isOpen: $slotMenuOpen, slot: $slot)      // hosts the floating card
/// ```
struct MealSlotDropdown: View {
    @Binding var slot: MealSlot
    @Binding var isOpen: Bool

    var body: some View {
        Button {
            HapticManager.shared.trigger(.light)
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { isOpen.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: slot.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(mealSlotColor(slot))
                Text(slot.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(mealSlotColor(slot).opacity(0.9))
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .glassEffect(.regular.tint(mealSlotColor(slot).opacity(0.28)).interactive(), in: Capsule())
            .overlay(Capsule().stroke(mealSlotColor(slot).opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        // Publish the trigger's frame so the host can anchor the card under it.
        .anchorPreference(key: MealSlotAnchorKey.self, value: .bounds) { $0 }
    }
}

// MARK: - Meal colours

/// Natural, distinct colour per meal — used for the trigger tint, icons, and the
/// selected-row highlight so the pull-down reads as one colour-coded system.
func mealSlotColor(_ s: MealSlot) -> Color {
    switch s {
    case .breakfast: return TagColor.orange.fg   // sunrise
    case .lunch:     return TagColor.yellow.fg   // midday sun
    case .dinner:    return TagColor.purple.fg   // night
    case .snacks:    return TagColor.green.fg    // veg
    }
}

// MARK: - Anchor plumbing

struct MealSlotAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

extension View {
    /// Host the floating menu card for a `MealSlotDropdown`. Apply once on the screen's
    /// outermost container so the scrim can cover the whole screen.
    func mealSlotMenu(isOpen: Binding<Bool>, slot: Binding<MealSlot>) -> some View {
        overlayPreferenceValue(MealSlotAnchorKey.self) { anchor in
            GeometryReader { geo in
                if isOpen.wrappedValue, let anchor {
                    let rect = geo[anchor]
                    let menuWidth = max(216, rect.width)
                    // Right-align the card when the trigger sits in the right half.
                    let rawX = rect.midX > geo.size.width / 2 ? rect.maxX - menuWidth : rect.minX
                    let x = min(max(12, rawX), geo.size.width - menuWidth - 12)

                    ZStack(alignment: .topLeading) {
                        Color.black.opacity(0.14)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture { close(isOpen) }
                            .transition(.opacity)

                        MealSlotMenuCard(current: slot.wrappedValue) { picked in
                            slot.wrappedValue = picked
                            close(isOpen)
                        }
                        .frame(width: menuWidth)
                        .offset(x: x, y: rect.maxY + 8)
                        .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
                    }
                }
            }
        }
    }
}

private func close(_ isOpen: Binding<Bool>) {
    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isOpen.wrappedValue = false }
}

// MARK: - Menu card

private struct MealSlotMenuCard: View {
    let current: MealSlot
    let onPick: (MealSlot) -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(MealSlot.allCases.enumerated()), id: \.element.id) { index, s in
                row(s, index: index)
                if s != MealSlot.allCases.last {
                    Divider().overlay(Theme.divider).padding(.leading, 50)
                }
            }
        }
        .padding(.vertical, 6)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
        .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { appeared = true } }
    }

    private func row(_ s: MealSlot, index: Int) -> some View {
        let selected = s == current
        return Button {
            HapticManager.shared.trigger(.selection)
            onPick(s)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: s.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(mealSlotColor(s))
                    .frame(width: 26)
                Text(s.rawValue)
                    .font(.system(size: 15, weight: selected ? .semibold : .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(mealSlotColor(s))
                    .opacity(selected ? 1 : 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? mealSlotColor(s).opacity(0.15) : .clear)
                    .padding(.horizontal, 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Subtle staggered entrance.
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -6)
        .animation(.spring(response: 0.34, dampingFraction: 0.86).delay(Double(index) * 0.04), value: appeared)
    }
}

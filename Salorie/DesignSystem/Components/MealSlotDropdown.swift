import SwiftUI

// MARK: - Shared glass dropdown infrastructure
//
// A custom Liquid-Glass pull-down (our palette, our motion — not the system `Menu`).
// A `DropdownTrigger` publishes its frame while open; a `.glassMenu(…)` host renders
// a floating `GlassMenuCard` anchored beneath it with a dim scrim. Multiple dropdowns
// can coexist on one screen: only the open trigger publishes its anchor, and each host
// renders only when its own `isOpen` is true.

struct DropdownAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// One option in a glass dropdown.
struct GlassMenuItem: Identifiable, Hashable {
    let id: String
    let title: String
    var systemImage: String? = nil
    var tint: Color? = nil
}

/// A tappable trigger that toggles `isOpen` and publishes its frame (only while open)
/// so the host can anchor the floating card beneath it.
struct DropdownTrigger<Label: View>: View {
    @Binding var isOpen: Bool
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button {
            HapticManager.shared.trigger(.light)
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { isOpen.toggle() }
        } label: { label() }
        .buttonStyle(.plain)
        .anchorPreference(key: DropdownAnchorKey.self, value: .bounds) { isOpen ? $0 : nil }
    }
}

extension View {
    /// Host a floating glass dropdown card for a `DropdownTrigger`. Apply on the screen's
    /// outermost container so the scrim can cover the whole screen. The card drops below
    /// the trigger by default, and flips *above* it when the trigger sits low on screen
    /// (e.g. a bottom action bar) so it never spills off the bottom edge.
    func glassMenu(isOpen: Binding<Bool>,
                   items: [GlassMenuItem],
                   selectedID: String,
                   accent: Color,
                   width: CGFloat = 200,
                   onSelect: @escaping (String) -> Void) -> some View {
        overlayPreferenceValue(DropdownAnchorKey.self) { anchor in
            GeometryReader { geo in
                if isOpen.wrappedValue, let anchor {
                    GlassMenuHost(rect: geo[anchor],
                                  container: geo.size,
                                  items: items,
                                  selectedID: selectedID,
                                  accent: accent,
                                  width: width,
                                  isOpen: isOpen,
                                  onSelect: onSelect)
                }
            }
        }
    }
}

/// Positions a `GlassMenuCard` beneath (or above) its trigger, measuring the card's
/// height so the upward flip lands flush against the trigger's top edge.
private struct GlassMenuHost: View {
    let rect: CGRect
    let container: CGSize
    let items: [GlassMenuItem]
    let selectedID: String
    let accent: Color
    let width: CGFloat
    @Binding var isOpen: Bool
    let onSelect: (String) -> Void

    @State private var cardHeight: CGFloat = 0

    var body: some View {
        let menuWidth = max(width, rect.width)
        let rawX = rect.midX > container.width / 2 ? rect.maxX - menuWidth : rect.minX
        let x = min(max(12, rawX), container.width - menuWidth - 12)

        // Flip up when a downward card wouldn't fit above the bottom safe margin.
        let flipUp = rect.maxY + 8 + cardHeight > container.height - 12
        let y = flipUp ? rect.minY - 8 - cardHeight : rect.maxY + 8

        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.14)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { closeMenu($isOpen) }
                .transition(.opacity)

            GlassMenuCard(items: items, selectedID: selectedID, accent: accent) { id in
                onSelect(id)
                closeMenu($isOpen)
            }
            .frame(width: menuWidth)
            .background(
                GeometryReader { g in
                    Color.clear.onAppear { cardHeight = g.size.height }
                        .onChange(of: g.size.height) { _, h in cardHeight = h }
                }
            )
            .offset(x: x, y: y)
            .transition(.scale(scale: 0.92, anchor: flipUp ? .bottom : .top).combined(with: .opacity))
        }
    }
}

private func closeMenu(_ isOpen: Binding<Bool>) {
    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isOpen.wrappedValue = false }
}

// MARK: - Card

private struct GlassMenuCard: View {
    let items: [GlassMenuItem]
    let selectedID: String
    let accent: Color
    let onSelect: (String) -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item, index: index)
                if item.id != items.last?.id {
                    Divider().overlay(Theme.divider)
                        .padding(.leading, item.systemImage != nil ? 50 : 18)
                }
            }
        }
        .padding(.vertical, 6)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
        .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { appeared = true } }
    }

    private func row(_ item: GlassMenuItem, index: Int) -> some View {
        let selected = item.id == selectedID
        let color = item.tint ?? accent
        return Button {
            HapticManager.shared.trigger(.selection)
            onSelect(item.id)
        } label: {
            HStack(spacing: 12) {
                if let icon = item.systemImage {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(color)
                        .frame(width: 26)
                }
                Text(item.title)
                    .font(.system(size: 15, weight: selected ? .semibold : .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
                    .opacity(selected ? 1 : 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(0.15))
                        .padding(.horizontal, 6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -6)
        .animation(.spring(response: 0.34, dampingFraction: 0.86).delay(Double(index) * 0.04), value: appeared)
    }
}

// MARK: - Meal colours

/// Natural, distinct colour per meal — trigger tint, icons, and selected-row highlight.
func mealSlotColor(_ s: MealSlot) -> Color {
    switch s {
    case .breakfast: return TagColor.orange.fg   // sunrise
    case .lunch:     return TagColor.yellow.fg   // midday sun
    case .dinner:    return TagColor.purple.fg   // night
    case .snacks:    return TagColor.green.fg    // veg
    }
}

// MARK: - Meal-slot dropdown (built on the shared infra)

struct MealSlotDropdown: View {
    @Binding var slot: MealSlot
    @Binding var isOpen: Bool

    var body: some View {
        DropdownTrigger(isOpen: $isOpen) {
            HStack(spacing: 8) {
                Image(systemName: slot.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(mealSlotColor(slot))
                Text(slot.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
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
    }
}

extension View {
    /// Host the meal-slot dropdown card. Apply once on the screen's container.
    func mealSlotMenu(isOpen: Binding<Bool>, slot: Binding<MealSlot>) -> some View {
        glassMenu(
            isOpen: isOpen,
            items: MealSlot.allCases.map {
                GlassMenuItem(id: $0.rawValue, title: $0.rawValue, systemImage: $0.symbol, tint: mealSlotColor($0))
            },
            selectedID: slot.wrappedValue.rawValue,
            accent: mealSlotColor(slot.wrappedValue),
            width: 216
        ) { id in
            if let s = MealSlot(rawValue: id) {
                withAnimation(.snappy) { slot.wrappedValue = s }
            }
        }
    }
}

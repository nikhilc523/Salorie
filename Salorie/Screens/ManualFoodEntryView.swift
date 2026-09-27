import SwiftUI

/// Create a food by hand — the final fallback when a barcode is in neither the
/// bundled catalog nor the live OFF/USDA lookup. "Scan Label" prefills the fields
/// via on-device OCR. Saving caches it (by barcode, so a re-scan resolves it) and
/// logs it to the chosen meal.
///
/// Redesigned as grouped cards on pure black (Apple "Add Workout" language, on our
/// palette): an identity card, a prominent Scan-Label card, a hierarchy-first
/// nutrition card (Calories + the three core macros up front; the five minor
/// nutrients tucked behind "More nutrients"), a serving card, and a colour-coded
/// meal-slot picker. Circular ✕ / ✓ chrome mirrors the reference.
struct ManualFoodEntryView: View {
    @Environment(MockStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var prefillBarcode: String?
    var initialSlot: MealSlot = .breakfast

    init(prefillBarcode: String? = nil, initialSlot: MealSlot = .breakfast) {
        self.prefillBarcode = prefillBarcode
        self.initialSlot = initialSlot
        _slot = State(initialValue: initialSlot)
    }

    @State private var name = ""
    @State private var brand = ""
    @State private var servingText = ""
    @State private var servingGrams = ""
    @State private var kcal = ""
    @State private var carbs = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var fibre = ""
    @State private var sugars = ""
    @State private var satfat = ""
    @State private var sodium = ""
    @State private var cholesterol = ""
    @State private var slot: MealSlot = .breakfast
    @State private var showLabelScanner = false
    @State private var showMore = false

    /// One case per text field. A shared `@FocusState Bool` bound to many fields has
    /// undefined focus behaviour (the cause of the "takes 3-4 taps" bug), so each field
    /// gets a distinct identity instead.
    private enum Field: Hashable {
        case name, brand, serving, weight, kcal, carbs, protein, fat
        case fibre, sugars, satfat, sodium, cholesterol
    }
    @FocusState private var focus: Field?

    /// Accent for "fat" — a warm tan that sits between the caramel/terracotta macros.
    private let fatTint = Color(hex: 0xCBB89B)

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !kcal.isEmpty && (Double(kcal) ?? -1) >= 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    identityCard
                    nutritionCard
                    servingCard
                    moreCard
                    logToCard
                }
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Theme.bg)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { closeButton }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if LabelScannerView.isSupported { scanLabelButton }
                    saveButton
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }
                        .fontWeight(.semibold)
                        .tint(RingColor.calories.tint)
                }
            }
            .fullScreenCover(isPresented: $showLabelScanner) {
                LabelScannerView(onResult: apply, onDismiss: { showLabelScanner = false })
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: Chrome

    private var closeButton: some View {
        Button {
            HapticManager.shared.trigger(.light)
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.surfaceRaised))
        }
        .buttonStyle(.plain)
    }

    private var saveButton: some View {
        Button {
            HapticManager.shared.trigger(.success)
            save()
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(canSave ? Color(hex: 0x1A1A1A) : Theme.textTertiary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(canSave ? RingColor.calories.tint : Theme.surfaceRaised))
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .accessibilityLabel("Save food")
    }

    // MARK: Identity

    private var identityCard: some View {
        cardContainer {
            HStack(spacing: 14) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(RingColor.calories.tint)
                    .frame(width: 52, height: 52)
                    .background(RingColor.calories.tint.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    TextField("Food name", text: $name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .tint(RingColor.calories.tint)
                        .focused($focus, equals: .name)
                        .submitLabel(.next)
                    TextField("Brand (optional)", text: $brand)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .tint(RingColor.calories.tint)
                        .focused($focus, equals: .brand)
                }
            }
        }
    }

    // MARK: Scan label — top-bar icon (OCR prefill), calorie-ring tone to match ✓

    private var scanLabelButton: some View {
        Button {
            HapticManager.shared.trigger(.light)
            showLabelScanner = true
        } label: {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RingColor.calories.tint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.surfaceRaised))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scan nutrition label")
    }

    // MARK: Nutrition (per serving)

    private var nutritionCard: some View {
        cardContainer {
            sectionLabel("NUTRITION · PER SERVING")
            calorieRow
            rowDivider
            macroRow("Carbs", tint: RingColor.carb.tint, unit: "g", text: $carbs, field: .carbs)
            rowDivider
            macroRow("Protein", tint: RingColor.protein.tint, unit: "g", text: $protein, field: .protein)
            rowDivider
            macroRow("Total Fat", tint: fatTint, unit: "g", text: $fat, field: .fat)
        }
    }

    /// Calories — the hero of the card: flame glyph + a larger oatmeal value.
    private var calorieRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(RingColor.calories.tint)
                .frame(width: 22)
            Text("Calories")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            valuePill(text: $kcal, unit: "kcal", field: .kcal, big: true, tint: RingColor.calories.tint)
        }
        .padding(.vertical, 12)
    }

    /// One macro row: colour dot + label + editable value pill.
    private func macroRow(_ label: String, tint: Color, unit: String, text: Binding<String>, field: Field) -> some View {
        HStack(spacing: 12) {
            Circle().fill(tint).frame(width: 11, height: 11).frame(width: 22)
            Text(label)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            valuePill(text: text, unit: unit, field: field)
        }
        .padding(.vertical, 12)
    }

    // MARK: Serving

    private var servingCard: some View {
        cardContainer {
            sectionLabel("SERVING")
            textRow(icon: "square.grid.2x2", label: "Description",
                    placeholder: "e.g. 1 package", text: $servingText, field: .serving)
            rowDivider
            HStack(spacing: 12) {
                Image(systemName: "scalemass")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 22)
                Text("Weight")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                valuePill(text: $servingGrams, unit: "g", field: .weight)
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: More nutrients (collapsed by default)

    private var moreCard: some View {
        cardContainer {
            Button {
                HapticManager.shared.trigger(.light)
                withAnimation(.snappy(duration: 0.28)) { showMore.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text("More nutrients")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Fibre · Sugars · Sodium…")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(showMore ? 180 : 0))
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showMore {
                VStack(spacing: 0) {
                    rowDivider
                    plainRow("Fibre", unit: "g", text: $fibre, field: .fibre)
                    rowDivider
                    plainRow("Sugars", unit: "g", text: $sugars, field: .sugars)
                    rowDivider
                    plainRow("Saturated Fat", unit: "g", text: $satfat, field: .satfat)
                    rowDivider
                    plainRow("Sodium", unit: "mg", text: $sodium, field: .sodium)
                    rowDivider
                    plainRow("Cholesterol", unit: "mg", text: $cholesterol, field: .cholesterol)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// A minor-nutrient row: quiet label + value pill, no colour dot.
    private func plainRow(_ label: String, unit: String, text: Binding<String>, field: Field) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            valuePill(text: text, unit: unit, field: field)
        }
        .padding(.vertical, 11)
    }

    // MARK: Log to — colour-coded meal-slot picker

    private var logToCard: some View {
        cardContainer {
            sectionLabel("LOG TO")
            HStack(spacing: 8) {
                ForEach(MealSlot.allCases) { s in
                    slotPill(s)
                }
            }
            .padding(.top, 2)
        }
    }

    private func slotPill(_ s: MealSlot) -> some View {
        let on = slot == s
        let color = mealSlotColor(s)
        return Button {
            HapticManager.shared.trigger(.selection)
            withAnimation(.snappy(duration: 0.22)) { slot = s }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: s.symbol)
                    .font(.system(size: 16, weight: .semibold))
                Text(s.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? color : Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(on ? color.opacity(0.16) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(on ? color.opacity(0.5) : Theme.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Shared building blocks

    private func cardContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).overlineStyle().padding(.bottom, 2)
    }

    private var rowDivider: some View {
        Rectangle().fill(Theme.divider).frame(height: 1)
    }

    /// A text row (non-numeric): icon + label + trailing free-text field.
    private func textRow(icon: String, label: String, placeholder: String, text: Binding<String>, field: Field) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            TextField(placeholder, text: text)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textPrimary)
                .tint(RingColor.calories.tint)
                .focused($focus, equals: field)
                .frame(maxWidth: 150)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { focus = field }
    }

    /// The editable value chip on the trailing edge — a decimal field + unit inside a
    /// raised capsule, so every number reads as one tappable pill (Apple-form style).
    private func valuePill(text: Binding<String>, unit: String, field: Field, big: Bool = false, tint: Color? = nil) -> some View {
        HStack(spacing: 4) {
            // Fixed width (no .fixedSize) gives a large, stable tap target — the tiny
            // content-sized field was why taps missed and it "took 3-4 tries".
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: big ? 19 : 16, weight: big ? .bold : .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint ?? Theme.textPrimary)
                .focused($focus, equals: field)
                .frame(width: big ? 62 : 52, alignment: .trailing)
            Text(unit)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Theme.surfaceRaised))
        .contentShape(Capsule())
        .onTapGesture { focus = field }   // tap anywhere in the pill to start typing
    }

    // MARK: OCR prefill

    private func apply(_ p: ParsedLabel) {
        func s(_ v: Double?) -> String { v.map { $0 == $0.rounded() ? String(Int($0)) : String($0) } ?? "" }
        if let g = p.servingGrams { servingGrams = s(g) }
        if let t = p.servingText, !t.isEmpty { servingText = t }
        if let v = p.calories { kcal = s(v) }
        if let v = p.carbs { carbs = s(v) }
        if let v = p.protein { protein = s(v) }
        if let v = p.fat { fat = s(v) }
        if let v = p.fibre { fibre = s(v) }
        if let v = p.sugars { sugars = s(v) }
        if let v = p.satfat { satfat = s(v) }
        if let v = p.sodium { sodium = s(v) }
        if let v = p.cholesterol { cholesterol = s(v) }
        // Surface the minor nutrients if OCR filled any, so the user can review them.
        if [p.fibre, p.sugars, p.satfat, p.sodium, p.cholesterol].contains(where: { $0 != nil }) {
            withAnimation(.snappy) { showMore = true }
        }
        HapticManager.shared.trigger(.success)
    }

    // MARK: Save

    private func save() {
        func d(_ t: String) -> Double { Double(t) ?? 0 }
        let grams = Double(servingGrams)
        let serving = servingText.trimmingCharacters(in: .whitespaces)
        let desc = !serving.isEmpty ? serving : (grams.map { "\(Int($0)) g" } ?? "1 serving")
        let food = Food(
            symbol: "fork.knife", tint: .gray,
            name: name.trimmingCharacters(in: .whitespaces),
            brand: brand.trimmingCharacters(in: .whitespaces).isEmpty ? nil : brand,
            source: .custom,
            servingDescription: desc,
            calories: Int(d(kcal).rounded()),
            carbs: d(carbs), protein: d(protein), fat: d(fat), fibre: d(fibre),
            sugars: d(sugars), saturatedFat: d(satfat), sodium: d(sodium), cholesterol: d(cholesterol),
            barcode: prefillBarcode?.isEmpty == false ? prefillBarcode : nil,
            servingGrams: grams
        )
        store.saveCustomFood(food)
        store.addEntry(food, slot: slot)
        dismiss()
    }
}

#Preview {
    ManualFoodEntryView()
        .environment(MockStore())
        .preferredColorScheme(.dark)
}

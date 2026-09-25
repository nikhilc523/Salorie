import SwiftUI

/// Create a food by hand — the final fallback when a barcode is in neither the
/// bundled catalog nor the live OFF/USDA lookup. "Scan Label" prefills the fields
/// via on-device OCR. Saving caches it (by barcode, so a re-scan resolves it) and
/// logs it to the chosen meal.
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

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (Double(kcal) ?? 0) >= 0 && !kcal.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if LabelScannerView.isSupported {
                    Section {
                        Button {
                            HapticManager.shared.trigger(.light)
                            showLabelScanner = true
                        } label: {
                            Label("Scan Nutrition Label", systemImage: "doc.text.viewfinder")
                                .foregroundStyle(RingColor.carb.tint)
                        }
                    } footer: {
                        Text("Point at the Nutrition Facts panel to fill the fields automatically.")
                    }
                }

                Section("Food") {
                    field("Name", text: $name)
                    field("Brand (optional)", text: $brand)
                    field("Serving (e.g. 1 package)", text: $servingText)
                    numberField("Serving weight", unit: "g", text: $servingGrams)
                }

                Section("Nutrition (per serving)") {
                    numberField("Calories", unit: "kcal", text: $kcal)
                    numberField("Carbs", unit: "g", text: $carbs)
                    numberField("Protein", unit: "g", text: $protein)
                    numberField("Total Fat", unit: "g", text: $fat)
                    numberField("Fibre", unit: "g", text: $fibre)
                    numberField("Sugars", unit: "g", text: $sugars)
                    numberField("Saturated Fat", unit: "g", text: $satfat)
                    numberField("Sodium", unit: "mg", text: $sodium)
                    numberField("Cholesterol", unit: "mg", text: $cholesterol)
                }

                Section("Log to") {
                    Picker("Meal", selection: $slot) {
                        ForEach(MealSlot.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.disabled(!canSave).fontWeight(.semibold)
                }
            }
            .fullScreenCover(isPresented: $showLabelScanner) {
                LabelScannerView(onResult: apply, onDismiss: { showLabelScanner = false })
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: Fields

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
    }

    private func numberField(_ title: String, unit: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
            Text(unit).foregroundStyle(Theme.textTertiary).frame(width: 32, alignment: .leading)
        }
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
        HapticManager.shared.trigger(.success)
        store.saveCustomFood(food)
        store.addEntry(food, slot: slot)
        dismiss()
    }
}

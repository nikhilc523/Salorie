import Foundation

/// All in-memory sample content. Swapped for a real store later with zero view changes.
enum SampleData {

    // MARK: Foods

    static let foods: [Food] = [
        Food(symbol: "cup.and.saucer.fill", tint: .blue, name: "Greek Yogurt, Plain", brand: "Fage",
             source: .usdaBranded, isOpen: false,
             tags: [Tag(text: "Homemade", color: .blue, filled: true), Tag(text: "Protein", color: .green)],
             servingDescription: "170 g (1 container)", calories: 100, carbs: 6, protein: 18, fat: 0, fibre: 0,
             ingredients: ["Pasteurized skimmed milk", "Live active yogurt cultures"], isFavorite: true),

        Food(symbol: "leaf.fill", tint: .green, name: "Avocado, Raw", brand: nil,
             source: .usdaFoundation, isOpen: true,
             tags: [Tag(text: "Good", color: .brown), Tag(text: "Satisfying", color: .pink)],
             servingDescription: "1 medium (150 g)", calories: 240, carbs: 13, protein: 3, fat: 22, fibre: 10,
             ingredients: ["Avocado"]),

        Food(symbol: "fork.knife", tint: .orange, name: "Grilled Chicken Breast", brand: nil,
             source: .srLegacy, isOpen: false,
             tags: [Tag(text: "Protein", color: .green), Tag(text: "Lean", color: .blue)],
             servingDescription: "100 g", calories: 165, carbs: 0, protein: 31, fat: 4, fibre: 0,
             ingredients: ["Chicken breast"], isFavorite: true),

        Food(symbol: "takeoutbag.and.cup.and.straw.fill", tint: .yellow, name: "Sourdough Bread", brand: "Boudin",
             source: .usdaBranded, isOpen: true,
             tags: [Tag(text: "Processed", color: .gray)],
             servingDescription: "1 slice (56 g)", calories: 150, carbs: 30, protein: 5, fat: 1, fibre: 2,
             ingredients: ["Enriched flour", "Water", "Salt", "Sourdough culture"]),

        Food(symbol: "circle.hexagongrid.fill", tint: .brown, name: "Almond Butter", brand: "Justin's",
             source: .openFoodFacts, isOpen: false,
             tags: [Tag(text: "Satisfying", color: .pink), Tag(text: "Good", color: .brown)],
             servingDescription: "2 tbsp (32 g)", calories: 190, carbs: 7, protein: 7, fat: 16, fibre: 3,
             ingredients: ["Dry roasted almonds"], isFavorite: true),

        Food(symbol: "leaf.fill", tint: .yellow, name: "Banana, Raw", brand: nil,
             source: .usdaFoundation, isOpen: false,
             tags: [Tag(text: "Snacks", color: .green)],
             servingDescription: "1 medium (118 g)", calories: 105, carbs: 27, protein: 1, fat: 0, fibre: 3),

        Food(symbol: "circle.fill", tint: .yellow, name: "Egg, Large", brand: nil,
             source: .srLegacy, isOpen: false,
             tags: [Tag(text: "Protein", color: .green)],
             servingDescription: "1 large (50 g)", calories: 72, carbs: 0, protein: 6, fat: 5, fibre: 0),

        Food(symbol: "circle.grid.3x3.fill", tint: .brown, name: "Brown Rice, Cooked", brand: nil,
             source: .srLegacy, isOpen: true,
             tags: [Tag(text: "Learning", color: .purple)],
             servingDescription: "1 cup (195 g)", calories: 218, carbs: 46, protein: 5, fat: 2, fibre: 4),

        Food(symbol: "waterbottle.fill", tint: .blue, name: "Protein Shake, Chocolate", brand: "Fairlife",
             source: .usdaBranded, isOpen: false,
             tags: [Tag(text: "Homemade", color: .blue, filled: true)],
             servingDescription: "1 bottle (340 mL)", calories: 150, carbs: 5, protein: 30, fat: 3, fibre: 1),

        Food(symbol: "leaf.fill", tint: .green, name: "Broccoli, Steamed", brand: nil,
             source: .usdaFoundation, isOpen: false,
             tags: [Tag(text: "Good", color: .brown), Tag(text: "Fibre", color: .green)],
             servingDescription: "1 cup (156 g)", calories: 55, carbs: 11, protein: 4, fat: 1, fibre: 5),

        Food(symbol: "square.grid.2x2.fill", tint: .brown, name: "Dark Chocolate 85%", brand: "Lindt",
             source: .openFoodFacts, isOpen: false,
             tags: [Tag(text: "Satisfying", color: .pink), Tag(text: "Processed", color: .gray)],
             servingDescription: "2 squares (20 g)", calories: 120, carbs: 8, protein: 2, fat: 10, fibre: 3),

        Food(symbol: "circle.fill", tint: .purple, name: "Blueberries, Raw", brand: nil,
             source: .usdaFoundation, isOpen: false,
             tags: [Tag(text: "Snacks", color: .green)],
             servingDescription: "1 cup (148 g)", calories: 84, carbs: 21, protein: 1, fat: 0, fibre: 4),
    ]

    // MARK: Targets

    static let targets = MacroTargets(calories: 2200, carbs: 250, protein: 140, fibre: 30, fat: 70)

    // MARK: Today's entries

    static func todayEntries() -> [MealEntry] {
        [
            MealEntry(food: foods[6], slot: .breakfast, servings: 2, time: "8:12 AM"),   // eggs
            MealEntry(food: foods[3], slot: .breakfast, servings: 1, time: "8:14 AM"),   // sourdough
            MealEntry(food: foods[0], slot: .breakfast, servings: 1, time: "8:20 AM"),   // yogurt
            MealEntry(food: foods[2], slot: .lunch, servings: 1.5, time: "12:45 PM"),    // chicken
            MealEntry(food: foods[7], slot: .lunch, servings: 1, time: "12:47 PM"),      // rice
            MealEntry(food: foods[9], slot: .lunch, servings: 1, time: "12:50 PM"),      // broccoli
            MealEntry(food: foods[5], slot: .snacks, servings: 1, time: "3:30 PM"),      // banana
            MealEntry(food: foods[4], slot: .snacks, servings: 1, time: "3:31 PM"),      // almond butter
            MealEntry(food: foods[10], slot: .snacks, servings: 1, time: "9:10 PM"),     // dark chocolate
        ]
    }

    // MARK: History (last 7 logged days)

    static func history() -> [DayLog] {
        let letters = ["S", "M", "T", "W", "T", "F", "S"]
        let calorieSpread = [1980, 2240, 2100, 1870, 2320, 2050, 1740]
        var days: [DayLog] = []
        let cal = Calendar.current
        let base = cal.startOfDay(for: SampleData.referenceDate)
        for i in 0..<7 {
            let date = cal.date(byAdding: .day, value: -(6 - i), to: base) ?? base
            // Build a rough entry set scaled to the target calories for the day.
            let scale = Double(calorieSpread[i]) / Double(foods[0].calories +
                foods[2].calories + foods[7].calories + foods[5].calories)
            let entries = [
                MealEntry(food: foods[0], slot: .breakfast, servings: scale, time: "8:00 AM"),
                MealEntry(food: foods[2], slot: .lunch, servings: scale, time: "1:00 PM"),
                MealEntry(food: foods[7], slot: .lunch, servings: scale, time: "1:05 PM"),
                MealEntry(food: foods[5], slot: .snacks, servings: scale, time: "4:00 PM"),
            ]
            days.append(DayLog(date: date, weekdayLetter: letters[i], entries: entries))
        }
        return days
    }

    /// Fixed "today" so previews and screenshots are deterministic (matches ref screens).
    static let referenceDate: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 4
        return Calendar.current.date(from: c) ?? Date(timeIntervalSince1970: 0)
    }()
}

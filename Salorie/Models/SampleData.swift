import Foundation

/// All in-memory sample content. Swapped for a real store later with zero view changes.
enum SampleData {

    // MARK: Foods

    static let foods: [Food] = [
        Food(symbol: "cup.and.saucer.fill", tint: .blue, name: "Greek Yogurt, Plain", brand: "Fage",
             source: .usdaBranded, isOpen: false,
             tags: [Tag(text: "Homemade", color: .blue, filled: true), Tag(text: "Protein", color: .green)],
             servingDescription: "170 g (1 container)", calories: 100, carbs: 6, protein: 18, fat: 0, fibre: 0, sugars: 7, saturatedFat: 0, sodium: 65, cholesterol: 10,
             ingredients: ["Pasteurized skimmed milk", "Live active yogurt cultures"], isFavorite: true),

        Food(symbol: "leaf.fill", tint: .green, name: "Avocado, Raw", brand: nil,
             source: .usdaFoundation, isOpen: true,
             tags: [Tag(text: "Good", color: .brown), Tag(text: "Satisfying", color: .pink)],
             servingDescription: "1 medium (150 g)", calories: 240, carbs: 13, protein: 3, fat: 22, fibre: 10, sugars: 1, saturatedFat: 3, sodium: 10, cholesterol: 0,
             ingredients: ["Avocado"]),

        Food(symbol: "fork.knife", tint: .orange, name: "Grilled Chicken Breast", brand: nil,
             source: .srLegacy, isOpen: false,
             tags: [Tag(text: "Protein", color: .green), Tag(text: "Lean", color: .blue)],
             servingDescription: "100 g", calories: 165, carbs: 0, protein: 31, fat: 4, fibre: 0, sugars: 0, saturatedFat: 1, sodium: 74, cholesterol: 85,
             ingredients: ["Chicken breast"], isFavorite: true),

        Food(symbol: "takeoutbag.and.cup.and.straw.fill", tint: .yellow, name: "Sourdough Bread", brand: "Boudin",
             source: .usdaBranded, isOpen: true,
             tags: [Tag(text: "Processed", color: .gray)],
             servingDescription: "1 slice (56 g)", calories: 150, carbs: 30, protein: 5, fat: 1, fibre: 2, sugars: 1, saturatedFat: 0, sodium: 320, cholesterol: 0,
             ingredients: ["Enriched flour", "Water", "Salt", "Sourdough culture"]),

        Food(symbol: "circle.hexagongrid.fill", tint: .brown, name: "Almond Butter", brand: "Justin's",
             source: .openFoodFacts, isOpen: false,
             tags: [Tag(text: "Satisfying", color: .pink), Tag(text: "Good", color: .brown)],
             servingDescription: "2 tbsp (32 g)", calories: 190, carbs: 7, protein: 7, fat: 16, fibre: 3, sugars: 2, saturatedFat: 1.5, sodium: 40, cholesterol: 0,
             ingredients: ["Dry roasted almonds"], isFavorite: true),

        Food(symbol: "leaf.fill", tint: .yellow, name: "Banana, Raw", brand: nil,
             source: .usdaFoundation, isOpen: false,
             tags: [Tag(text: "Snacks", color: .green)],
             servingDescription: "1 medium (118 g)", calories: 105, carbs: 27, protein: 1, fat: 0, fibre: 3, sugars: 14, saturatedFat: 0, sodium: 1, cholesterol: 0),

        Food(symbol: "circle.fill", tint: .yellow, name: "Egg, Large", brand: nil,
             source: .srLegacy, isOpen: false,
             tags: [Tag(text: "Protein", color: .green)],
             servingDescription: "1 large (50 g)", calories: 72, carbs: 0, protein: 6, fat: 5, fibre: 0, sugars: 0, saturatedFat: 1.6, sodium: 71, cholesterol: 186),

        Food(symbol: "circle.grid.3x3.fill", tint: .brown, name: "Brown Rice, Cooked", brand: nil,
             source: .srLegacy, isOpen: true,
             tags: [Tag(text: "Learning", color: .purple)],
             servingDescription: "1 cup (195 g)", calories: 218, carbs: 46, protein: 5, fat: 2, fibre: 4, sugars: 1, saturatedFat: 0.4, sodium: 10, cholesterol: 0),

        Food(symbol: "waterbottle.fill", tint: .blue, name: "Protein Shake, Chocolate", brand: "Fairlife",
             source: .usdaBranded, isOpen: false,
             tags: [Tag(text: "Homemade", color: .blue, filled: true)],
             servingDescription: "1 bottle (340 mL)", calories: 150, carbs: 5, protein: 30, fat: 3, fibre: 1, sugars: 2, saturatedFat: 1, sodium: 200, cholesterol: 30),

        Food(symbol: "leaf.fill", tint: .green, name: "Broccoli, Steamed", brand: nil,
             source: .usdaFoundation, isOpen: false,
             tags: [Tag(text: "Good", color: .brown), Tag(text: "Fibre", color: .green)],
             servingDescription: "1 cup (156 g)", calories: 55, carbs: 11, protein: 4, fat: 1, fibre: 5, sugars: 2, saturatedFat: 0, sodium: 64, cholesterol: 0),

        Food(symbol: "square.grid.2x2.fill", tint: .brown, name: "Dark Chocolate 85%", brand: "Lindt",
             source: .openFoodFacts, isOpen: false,
             tags: [Tag(text: "Satisfying", color: .pink), Tag(text: "Processed", color: .gray)],
             servingDescription: "2 squares (20 g)", calories: 120, carbs: 8, protein: 2, fat: 10, fibre: 3, sugars: 3, saturatedFat: 5, sodium: 4, cholesterol: 2),

        Food(symbol: "circle.fill", tint: .purple, name: "Blueberries, Raw", brand: nil,
             source: .usdaFoundation, isOpen: false,
             tags: [Tag(text: "Snacks", color: .green)],
             servingDescription: "1 cup (148 g)", calories: 84, carbs: 21, protein: 1, fat: 0, fibre: 4, sugars: 15, saturatedFat: 0, sodium: 1, cholesterol: 0),

        // Demo item you can scan — encode "SALORIE-DEMO-01" (see the generated Code128 PNG).
        Food(symbol: "takeoutbag.and.cup.and.straw.fill", tint: .orange, name: "Protein Bar (Demo)", brand: "Salorie",
             source: .openFoodFacts, isOpen: false,
             tags: [Tag(text: "Scanned", color: .blue, filled: true)],
             servingDescription: "1 bar (60 g)", calories: 230, carbs: 24, protein: 20, fat: 8, fibre: 5, sugars: 6, saturatedFat: 3, sodium: 140, cholesterol: 5,
             ingredients: ["Protein blend", "Almonds", "Dates", "Cocoa"], barcode: "SALORIE-DEMO-01"),
    ]

    // MARK: Custom meals (user-built composites of the foods above)

    static func customMeals() -> [Food] {
        [
            Food.customMeal(
                name: "Protein Oat Bowl", symbol: "cup.and.saucer.fill", tint: .brown, isFavorite: true,
                components: [
                    MealComponent(food: foods[0], servings: 1),   // greek yogurt
                    MealComponent(food: foods[5], servings: 1),   // banana
                    MealComponent(food: foods[4], servings: 1),   // almond butter
                    MealComponent(food: foods[11], servings: 1),  // blueberries
                ]),
            Food.customMeal(
                name: "Chicken Rice Bowl", symbol: "takeoutbag.and.cup.and.straw.fill", tint: .green,
                components: [
                    MealComponent(food: foods[2], servings: 1.5), // chicken
                    MealComponent(food: foods[7], servings: 1),   // brown rice
                    MealComponent(food: foods[9], servings: 1),   // broccoli
                ]),
        ]
    }

    // MARK: Targets

    static let targets = MacroTargets(calories: 2200, carbs: 250, protein: 140, fibre: 30, fat: 70)

    // MARK: Today's entries

    static func todayEntries() -> [MealEntry] {
        [
            MealEntry(food: customMeals()[0], slot: .breakfast, servings: 1, time: "8:05 AM"), // Protein Oat Bowl
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

    // MARK: Extended daily log (for History trends — Week / Month / Year)

    /// A longer, deterministic run of logged days ending at `referenceDate`, so the
    /// History screen has real data to aggregate across periods. No randomness — values
    /// come from a smooth wave + weekday effect so previews/screenshots are stable.
    static func extendedHistory(days: Int = 120) -> [DayLog] {
        let cal = Calendar.current
        let base = cal.startOfDay(for: referenceDate)
        let letters = ["S", "M", "T", "W", "T", "F", "S"]
        let baseSum = Double(foods[0].calories + foods[2].calories + foods[7].calories + foods[5].calories)
        var out: [DayLog] = []
        for back in stride(from: days - 1, through: 0, by: -1) {
            let date = cal.date(byAdding: .day, value: -back, to: base) ?? base
            let weekday = cal.component(.weekday, from: date)        // 1 = Sun … 7 = Sat
            let idx = days - 1 - back
            let wave = 210.0 * sin(Double(idx) / 4.3)                // slow rise/fall
            let weekend = (weekday == 1 || weekday == 7) ? 190.0 : -35.0
            let drift = Double((idx * 7) % 90) - 45.0                // pseudo day-to-day jitter
            let dayCalories = max(1500.0, 2080.0 + wave + weekend + drift * 0.5)
            let scale = dayCalories / baseSum
            let entries = [
                MealEntry(food: foods[0], slot: .breakfast, servings: scale, time: "8:00 AM"),
                MealEntry(food: foods[2], slot: .lunch, servings: scale, time: "1:00 PM"),
                MealEntry(food: foods[7], slot: .lunch, servings: scale, time: "1:05 PM"),
                MealEntry(food: foods[5], slot: .snacks, servings: scale, time: "4:00 PM"),
            ]
            out.append(DayLog(date: date, weekdayLetter: letters[(weekday - 1) % 7], entries: entries))
        }
        return out
    }

    // MARK: Sharing — friends (mock now, CloudKit CKShare later)

    /// The 7 dates ending at `referenceDate`, with weekday letters, used to lay out
    /// every friend's Last-7-Days strip on the same calendar.
    static func last7Scaffold() -> [(date: Date, letter: String)] {
        let cal = Calendar.current
        let base = cal.startOfDay(for: referenceDate)
        let letters = ["S", "M", "T", "W", "T", "F", "S"]
        return (0..<7).map { i in
            let date = cal.date(byAdding: .day, value: -(6 - i), to: base) ?? base
            return (date, letters[(cal.component(.weekday, from: date) - 1) % 7])
        }
    }

    /// A Last-7 strip with no shared data (all days nil) — for pending friends.
    static func emptyLast7() -> [FriendDay] {
        last7Scaffold().map { FriendDay(date: $0.date, weekdayLetter: $0.letter, progress: nil) }
    }

    /// A Last-7 strip driven by a per-day multiplier of the given goals.
    private static func last7(goalCal: Int, goalProtein: Double, goalCarbs: Double, spread: [Double]) -> [FriendDay] {
        zip(last7Scaffold(), spread).map { slot, k in
            FriendDay(date: slot.date, weekdayLetter: slot.letter,
                      progress: RingProgress(
                          caloriesPct: k, proteinPct: min(k * 0.95, 1.2), carbsPct: min(k * 1.05, 1.3),
                          consumedCal: Int(Double(goalCal) * k), goalCal: goalCal))
        }
    }

    /// Friends other than "Me" (which the store builds from its own data):
    /// one sharing full data, one pending (not shared), one at 0%.
    static func otherFriends() -> [SharedFriend] {
        let aaravGoal = 2000
        let aarav = SharedFriend(
            name: "Aarav", avatar: "figure.run", avatarTint: .green, appleID: "aarav.k@icloud.com",
            hasShared: true,
            today: RingProgress(caloriesPct: 0.86, proteinPct: 1.02, carbsPct: 0.74,
                                consumedCal: 1720, goalCal: aaravGoal),
            last7: last7(goalCal: aaravGoal, goalProtein: 130, goalCarbs: 220,
                         spread: [0.7, 0.95, 0.82, 1.05, 0.6, 0.9, 0.86]))

        let niharika = SharedFriend(
            name: "Niharika", avatar: "pawprint.fill", avatarTint: .brown,
            appleID: "51c9de96-2d5a-4035-8873-358088eaf06b@inbox.appleid.apple.com",
            hasShared: false, today: nil, last7: emptyLast7())

        let srishti = SharedFriend(
            name: "Srishti", avatar: "hare.fill", avatarTint: .purple, appleID: "srishti@privaterelay.appleid.com",
            hasShared: true,
            today: RingProgress(caloriesPct: 0, proteinPct: 0, carbsPct: 0,
                                consumedCal: 0, goalCal: 1800),
            last7: last7Scaffold().map {
                FriendDay(date: $0.date, weekdayLetter: $0.letter,
                          progress: RingProgress(caloriesPct: 0, proteinPct: 0, carbsPct: 0,
                                                 consumedCal: 0, goalCal: 1800))
            })

        return [aarav, niharika, srishti]
    }

    /// Fixed "today" so previews and screenshots are deterministic (matches ref screens).
    static let referenceDate: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 4
        return Calendar.current.date(from: c) ?? Date(timeIntervalSince1970: 0)
    }()
}

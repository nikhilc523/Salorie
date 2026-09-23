import SwiftUI

/// History — monthly progress, compliance stats, mini per-day rings, and a log table.
struct HistoryView: View {
    @Environment(MockStore.self) private var store
    @State private var selectedFood: Food?
    @State private var showDayDetail = false
    @State private var dayIndex = 0

    private var perfectDays: Int {
        store.history.filter { Double($0.calories) <= Double(store.targets.calories) * 1.05 }.count
    }
    private var weekProgress: Int {
        let avg = store.history.map(\.calories).reduce(0, +) / max(1, store.history.count)
        return Int((Double(avg) / Double(store.targets.calories) * 100).rounded())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NotionPageHeader(symbol: "chart.xyaxis.line", tint: .green, title: "History",
                                     subtitle: "Your last 7 days at a glance")

                    statsRow
                    weekRingsCard
                    logTable
                }
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.bottom, 24)
            }
            .background(Theme.bg)
            .scrollContentBackground(.hidden)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedFood) { FoodDetailView(food: $0) }
            .sheet(isPresented: $showDayDetail) { DayDetailView(initialIndex: dayIndex) }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            MetricCard(label: "Week Progress", value: "\(weekProgress)%",
                       icon: "chart.line.uptrend.xyaxis", accent: TagColor.green.fg,
                       footnote: "avg vs. goal")
            MetricCard(label: "On-Target Days", value: "\(perfectDays) / \(store.history.count)",
                       icon: "checkmark.seal.fill", accent: Theme.textPrimary,
                       footnote: "within 5% of goal")
        }
    }

    private var weekRingsCard: some View {
        CalmCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("MONTHLY HISTORY").overlineStyle()
                    Spacer()
                    StatPill(text: "\(weekProgress)%", color: .green)
                }
                HStack(spacing: 0) {
                    ForEach(Array(store.history.enumerated()), id: \.element.id) { i, day in
                        Button {
                            HapticManager.shared.trigger(.selection)
                            dayIndex = i
                            showDayDetail = true
                        } label: {
                            VStack(spacing: 10) {
                                MiniDayRing(rings: rings(for: day), size: 40, lineWidth: 4.5)
                                Text(day.weekdayLetter)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.textTertiary)
                                Text("\(day.calories)")
                                    .font(.system(size: 10, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func rings(for day: DayLog) -> [Ring] {
        [
            Ring(progress: day.carbs / store.targets.carbs, color: .carb, label: "Carb", valueText: ""),
            Ring(progress: day.protein / store.targets.protein, color: .protein, label: "Protein", valueText: ""),
            Ring(progress: day.fibre / store.targets.fibre, color: .fibre, label: "Fibre", valueText: ""),
        ]
    }

    private var logTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DAILY LOG").overlineStyle()
            NotionTable(
                columns: [
                    NotionColumn(title: "Cal", icon: "flame", width: 66, alignment: .trailing),
                    NotionColumn(title: "Protein", icon: "bolt.fill", width: 88),
                    NotionColumn(title: "Carb", icon: "leaf.fill", width: 80),
                    NotionColumn(title: "Fibre", icon: "circle.grid.cross", width: 76),
                    NotionColumn(title: "Status", icon: "flag", width: 110),
                ],
                rows: store.history.reversed().map { day in
                    let onTarget = Double(day.calories) <= Double(store.targets.calories) * 1.05
                    return NotionRow(
                        icon: "calendar",
                        tint: .blue,
                        name: day.date.formatted(.dateTime.weekday(.abbreviated).month().day()),
                        cells: [
                            .number("\(day.calories)"),
                            .macro(.protein, "\(Int(day.protein))g"),
                            .macro(.carb, "\(Int(day.carbs))g"),
                            .macro(.fibre, "\(Int(day.fibre))g"),
                            .tags([Tag(text: onTarget ? "On target" : "Over",
                                       color: onTarget ? .green : .red)]),
                        ]
                    )
                },
                showNewRow: false
            )
        }
    }
}

#Preview {
    HistoryView()
        .environment(MockStore())
        .preferredColorScheme(.dark)
}

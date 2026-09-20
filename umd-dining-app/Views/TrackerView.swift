import Charts
import SwiftData
import SwiftUI

struct TrackerView: View {
    @Binding var tabResetID: UUID
    @Environment(NutritionTrackerManager.self) private var tracker
    @Environment(\.modelContext) private var modelContext
    @State private var selectedDate = Date()
    @State private var showClearConfirm = false
    @State private var animateCharts = false
    @State private var entries: [TrackedEntry] = []
    @State private var scrollProxy: ScrollViewProxy?
    @State private var hasAppeared = false
    @Namespace private var namespace

    // Edit serving picker state
    @State private var editingEntry: TrackedEntry?
    @State private var editNutrition: [String: String] = [:]
    @State private var editServingCount: Double = 1.0
    @State private var editLoadingRecNum: String?

    // Display values that drive chart animations (animate between these)
    @State private var displayCalorieValue: Int = 0
    @State private var displayProteinValue: Double = 0
    @State private var displayCarbsValue: Double = 0
    @State private var displayFatValue: Double = 0

    private var totalCalories: Int {
        entries.reduce(0) { $0 + $1.calories }
    }

    private var totalProtein: Double {
        entries.reduce(0) { $0 + $1.proteinG }
    }

    private var totalCarbs: Double {
        entries.reduce(0) { $0 + $1.carbsG }
    }

    private var totalFat: Double {
        entries.reduce(0) { $0 + $1.fatG }
    }

    private var calorieGoal: Int {
        tracker.calorieGoalSetting
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var proteinMet: Bool { tracker.proteinGoal > 0 && Int(totalProtein) >= tracker.proteinGoal }
    private var carbsMet: Bool { tracker.carbsGoal > 0 && Int(totalCarbs) >= tracker.carbsGoal }
    private var fatMet: Bool { tracker.fatGoal > 0 && Int(totalFat) >= tracker.fatGoal }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                trackerContent
            }
            .background(Color.umdBackground)
        }
        .id(tabResetID)
        .overlay {
            if showClearConfirm {
                clearConfirmOverlay
            }
        }
        .fullScreenCover(item: $editingEntry) { entry in
            ServingPickerSheet(
                foodName: entry.foodName,
                nutrition: editNutrition,
                servingCount: $editServingCount,
                onLog: {
                    tracker.setModelContext(modelContext)
                    tracker.updateEntry(entry, nutrition: editNutrition,
                                        servingMultiplier: editServingCount)
                    loadEntries()
                    withAnimation(.easeOut(duration: 0.5)) {
                        displayCalorieValue = totalCalories
                        displayProteinValue = totalProtein
                        displayCarbsValue = totalCarbs
                        displayFatValue = totalFat
                    }
                    editingEntry = nil
                },
                onCancel: { editingEntry = nil }
            )
            .presentationBackground(.clear)
        }
        .onAppear {
            tracker.setModelContext(modelContext)
            if !hasAppeared {
                // First ever appearance: animate from 0
                selectedDate = Date()
                loadEntries()
                displayCalorieValue = 0
                displayProteinValue = 0
                displayCarbsValue = 0
                displayFatValue = 0
                animateCharts = true
                withAnimation(.easeOut(duration: 0.8)) {
                    displayCalorieValue = totalCalories
                    displayProteinValue = totalProtein
                    displayCarbsValue = totalCarbs
                    displayFatValue = totalFat
                }
                hasAppeared = true
            }
        }
        .onChange(of: selectedDate) {
            // Date change: animate from current display values to new day's values
            loadEntries()
            withAnimation(.easeOut(duration: 0.8)) {
                displayCalorieValue = totalCalories
                displayProteinValue = totalProtein
                displayCarbsValue = totalCarbs
                displayFatValue = totalFat
            }
        }
        .onChange(of: tabResetID) {
            // Tab re-selected: only re-animate if coming back from another tab
            let wasOnTab = hasAppeared
            selectedDate = Date()
            loadEntries()
            if wasOnTab {
                // Came back from another tab: animate from 0, no delay
                displayCalorieValue = 0
                displayProteinValue = 0
                displayCarbsValue = 0
                displayFatValue = 0
                animateCharts = true
                withAnimation(.easeOut(duration: 0.8)) {
                    displayCalorieValue = totalCalories
                    displayProteinValue = totalProtein
                    displayCarbsValue = totalCarbs
                    displayFatValue = totalFat
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Tracker")
                .font(.inter(size: 22, weight: .bold))
                .foregroundStyle(Color.umdRed)

            Spacer()

            NavigationLink(destination: GoalsView()) {
                HStack(spacing: 5) {
                    Image(systemName: "target")
                        .font(.system(size: 16, weight: .medium))
                    Text("Goals")
                        .font(.inter(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color.umdRed)
                .frame(height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Content

    private var trackerContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    Color.clear.frame(height: 0).id("trackerTop")
                    dateSelector
                    calorieRingCard
                    SectionHeader(title: "Macros")
                    macroCards
                    loggedItemsSection
                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            .onAppear { scrollProxy = proxy }
        }
    }

    // MARK: - Date Selector

    private var dateSelector: some View {
        HStack {
            Button {
                withAnimation { selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)! }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.umdRed)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            CalendarCardButton(selection: $selectedDate)

            Spacer()

            Button {
                withAnimation { selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)! }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(isToday ? Color.gray.opacity(0.3) : Color.umdRed)
                    .frame(width: 44, height: 44)
            }
            .disabled(isToday)
        }
    }

    private var dateLabel: String {
        if isToday { return "Today" }
        if Calendar.current.isDateInYesterday(selectedDate) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: selectedDate)
    }

    // MARK: - Calorie Ring (Full Width)

    private var calorieRingCard: some View {
        ZStack {
            Chart {
                SectorMark(
                    angle: .value("Consumed", min(displayCalorieValue, calorieGoal)),
                    innerRadius: .ratio(0.7),
                    angularInset: 2
                )
                .foregroundStyle(Color.umdRed)
                .cornerRadius(4)

                SectorMark(
                    angle: .value("Remaining", max(0, calorieGoal - displayCalorieValue)),
                    innerRadius: .ratio(0.7),
                    angularInset: 2
                )
                .foregroundStyle(Color.umdRed.opacity(0.15))
                .cornerRadius(4)
            }
            .frame(height: 220)
            .animation(.easeOut(duration: 0.8), value: displayCalorieValue)

            VStack(spacing: 4) {
                Text("\(totalCalories)")
                    .font(.inter(size: 42, weight: .bold))
                    .foregroundStyle(Color.umdRed)
                Text("OF \(calorieGoal) CAL")
                    .font(.inter(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .kerning(0.3)
            }
        }
        .padding()
        .homeCard(tint: .clear)
    }

    // MARK: - Macro Cards (one per macro, bottom-up fill with goal)

    private var macroCards: some View {
        HStack(spacing: 10) {
            macroCard(label: "Protein", consumed: displayProteinValue, goal: Double(tracker.proteinGoal), color: .blue, met: proteinMet && animateCharts)
            macroCard(label: "Carbs", consumed: displayCarbsValue, goal: Double(tracker.carbsGoal), color: .green, met: carbsMet && animateCharts)
            macroCard(label: "Fat", consumed: displayFatValue, goal: Double(tracker.fatGoal), color: .orange, met: fatMet && animateCharts)
        }
        .animation(.easeOut(duration: 0.8), value: displayProteinValue)
        .animation(.easeOut(duration: 0.8), value: displayCarbsValue)
        .animation(.easeOut(duration: 0.8), value: displayFatValue)
        .animation(.easeInOut(duration: 0.5), value: tracker.proteinGoal)
        .animation(.easeInOut(duration: 0.5), value: tracker.carbsGoal)
        .animation(.easeInOut(duration: 0.5), value: tracker.fatGoal)
    }

    private func macroCard(label: String, consumed: Double, goal: Double, color: Color, met: Bool) -> some View {
        let maxVal = max(goal, consumed, 1)
        let goalRatio = goal > 0 ? goal / maxVal : 0
        let consumedRatio = consumed / maxVal

        return VStack(spacing: 10) {
            // Label + star
            HStack(spacing: 3) {
                Text(label.uppercased())
                    .font(.inter(size: 11, weight: .bold))
                    .kerning(1)
                    .foregroundStyle(color)
                if met {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(color)
                }
            }

            // Bar
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    // Goal background (full translucent bar)
                    if goal > 0 {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(color.opacity(0.12))
                            .frame(height: geo.size.height * goalRatio)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }

                    // Consumed fill (solid, bottom-up)
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color)
                        .frame(height: geo.size.height * min(consumedRatio, 1.0))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(width: 64, height: 120)

            // Consumed / goal
            VStack(spacing: 2) {
                Text("\(Int(consumed))g")
                    .font(.inter(size: 18, weight: .bold))
                    .foregroundStyle(color)
                Text(goal > 0 ? "OF \(Int(goal))G" : "NO GOAL")
                    .font(.inter(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .kerning(0.3)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .homeCard(tint: color)
    }

    // MARK: - Logged Items

    private var loggedItemsSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Logged Items", trailing: entries.isEmpty ? nil : "\(entries.count) \(entries.count == 1 ? "item" : "items")")

            if entries.isEmpty {
                Text("Tap + on any food to start tracking")
                    .font(.inter(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }

            ForEach(entries) { entry in
                NavigationLink(destination: NutritionDetailView(
                    recNum: entry.recNum,
                    foodName: entry.foodName,
                    diningHallName: entry.diningHall,
                    source: "tracker"
                )
                .navigationTransition(.zoom(sourceID: "tracker-\(entry.id)", in: namespace))
                ) {
                    loggedItemRow(entry)
                }
                .matchedTransitionSource(id: "tracker-\(entry.id)", in: namespace)
                .buttonStyle(.plain)
            }

            if !entries.isEmpty {
                Button {
                    showClearConfirm = true
                } label: {
                    Text("Clear All")
                        .font(.inter(size: 15, weight: .semibold))
                        .foregroundStyle(Color.umdRed)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .homeCard()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func loggedItemRow(_ entry: TrackedEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.foodName)
                    .font(.inter(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(entry.calories) CAL · \(timeString(from: entry.loggedAt))")
                    .font(.inter(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .kerning(0.3)

                FlowLayout(spacing: 4) {
                    macroTag("\(Int(entry.proteinG))g protein", color: .blue)
                    macroTag("\(Int(entry.carbsG))g carbs", color: .green)
                    macroTag("\(Int(entry.fatG))g fat", color: .orange)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                Button {
                    beginEdit(entry)
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.umdRed.opacity(0.25), lineWidth: 1.5)
                            .frame(width: 36, height: 36)
                        if editLoadingRecNum == entry.recNum {
                            ProgressView().frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.umdRed)
                        }
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(editLoadingRecNum != nil)

                Button {
                    removeEntry(entry)
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.umdRed.opacity(0.25), lineWidth: 1.5)
                            .frame(width: 36, height: 36)
                        Image(systemName: "minus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.umdRed)
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .homeCard()
        .transition(.asymmetric(
            insertion: .opacity,
            removal: .opacity.combined(with: .slide)
        ))
    }

    private func macroTag(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.inter(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Clear Confirm Overlay

    private var clearConfirmOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { showClearConfirm = false }

            VStack(spacing: 16) {
                Text("Clear All Items?")
                    .font(.inter(size: 18, weight: .bold))

                Text("This will remove all \(entries.count) logged items for \(dateLabel.lowercased()).")
                    .font(.inter(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button {
                        showClearConfirm = false
                    } label: {
                        Text("Cancel")
                            .font(.inter(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showClearConfirm = false
                        clearAllEntries()
                    } label: {
                        Text("Clear All")
                            .font(.inter(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.umdRed)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 20)
            .padding(.horizontal, 30)
        }
    }

    // MARK: - Helpers

    private func loadEntries() {
        entries = tracker.entries(for: selectedDate)
    }

    private func beginEdit(_ entry: TrackedEntry) {
        editLoadingRecNum = entry.recNum
        Task {
            var info = await NutritionCache.shared.get(entry.recNum)
            if info == nil {
                info = try? await DiningAPIService.shared.fetchNutrition(recNum: entry.recNum)
                if let info { await NutritionCache.shared.set(entry.recNum, info) }
            }
            editLoadingRecNum = nil
            guard let info else { return }
            editNutrition = info.nutrition
            editServingCount = entry.servingMultiplier > 0 ? entry.servingMultiplier : 1.0
            editingEntry = entry
        }
    }

    private func removeEntry(_ entry: TrackedEntry) {
        tracker.setModelContext(modelContext)
        tracker.removeEntry(entry)
        withAnimation(.easeInOut(duration: 0.35)) {
            entries.removeAll { $0.id == entry.id }
        }
    }

    private func clearAllEntries() {
        tracker.setModelContext(modelContext)
        tracker.clearDay(selectedDate)
        withAnimation(.easeInOut(duration: 0.35)) {
            entries.removeAll()
        }
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

#Preview {
    TrackerView(tabResetID: .constant(UUID()))
        .environment(NutritionTrackerManager.shared)
        .modelContainer(for: [DailyLog.self, TrackedEntry.self])
}

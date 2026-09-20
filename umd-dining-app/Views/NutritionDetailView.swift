import SwiftData
import SwiftUI

struct NutritionDetailView: View {
    let recNum: String
    let foodName: String
    var station: String? = nil
    var diningHallName: String? = nil
    var source: String = "unknown"
    var tags: [String] = []
    @State private var viewModel = NutritionViewModel()
    @Environment(FavoritesManager.self) private var favorites
    @Environment(NutritionTrackerManager.self) private var tracker
    @Environment(\.modelContext) private var modelContext
    @State private var showAddedToTracker = false
    @State private var showServingPicker = false
    @State private var servingCount: Double = 1.0

    // Already shown elsewhere — exclude from table
    private let excludeFromTable = ["Calories", "Total Fat", "Total Carbohydrate", "Protein",
                                     "Serving Size", "Servings Per Container"]

    // Key nutrients shown by default
    private let keyNutrients = ["Cholesterol", "Sodium", "Total Sugars", "Saturated Fat", "Calcium", "Potassium"]

    @State private var showAllNutrition = false
    @State private var showSimilarFoods = false
    @State private var selectedSimilarItem: MenuItem?
    @Namespace private var namespace

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading nutrition info...")
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        Task { await viewModel.loadNutrition(recNum: recNum) }
                    }
                }
            } else if let info = viewModel.nutritionInfo {
                nutritionContent(info)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    // Add to tracker button
                    Button {
                        servingCount = 1.0
                        showServingPicker = true
                    } label: {
                        if showAddedToTracker {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(Color.umdRed)
                        }
                    }
                    .disabled(viewModel.nutritionInfo == nil || showAddedToTracker)

                    // Favorite button
                    Button {
                        favorites.toggleFood(recNum: recNum, name: foodName)
                    } label: {
                        Image(systemName: favorites.isFavorite(recNum: recNum) ? "heart.fill" : "heart")
                            .foregroundStyle(favorites.isFavorite(recNum: recNum) ? Color.umdRed : .gray)
                    }
                }
            }
        }
        .task {
            await viewModel.loadNutrition(recNum: recNum)
            DiningAPIService.shared.trackItemView(recNum: recNum, foodName: foodName, source: source)
        }
        .task {
            let dateForSimilar: String? = (station == nil) ? todayDateString() : nil
            await viewModel.loadSimilarFoods(recNum: recNum, date: dateForSimilar)
        }
        .navigationDestination(item: $selectedSimilarItem) { item in
            let hallName = Self.hallNames[item.diningHallId] ?? ""
            NutritionDetailView(
                recNum: item.recNum,
                foodName: item.name,
                station: item.station.isEmpty ? nil : item.station,
                diningHallName: hallName.isEmpty ? nil : hallName,
                source: "similar"
            )
            .navigationTransition(.zoom(sourceID: "similar-\(item.recNum)", in: namespace))
        }
        .fullScreenCover(isPresented: $showServingPicker) {
            if let info = viewModel.nutritionInfo {
                ServingPickerSheet(
                    foodName: foodName,
                    nutrition: info.nutrition,
                    servingCount: $servingCount,
                    onLog: {
                        tracker.setModelContext(modelContext)
                        tracker.addEntry(name: foodName, recNum: recNum, nutrition: info.nutrition,
                                         mealPeriod: nil, diningHall: diningHallName,
                                         servingMultiplier: servingCount)
                        Task { await NutritionCache.shared.set(recNum, info) }
                        showServingPicker = false
                        servingCount = 1.0
                        withAnimation(.spring(duration: 0.3)) { showAddedToTracker = true }
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            withAnimation { showAddedToTracker = false }
                        }
                    },
                    onCancel: {
                        showServingPicker = false
                        servingCount = 1.0
                    }
                )
                .presentationBackground(.clear)
            }
        }
    }

    private func nutritionContent(_ info: NutritionInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Food name — wraps for long names
                Text(foodName)
                    .font(.inter(size: 24, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)

                if !tags.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(tags, id: \.self) { tag in
                            DietaryTag(text: DietaryStyles.tagLabel(for: tag))
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Hero card — serving info left, calories right
                let servingSize = nutritionValue("Serving Size", from: info.nutrition)
                let servingsPerContainer = nutritionValue("Servings Per Container", from: info.nutrition)
                let calories = nutritionValue("Calories", from: info.nutrition)

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let size = servingSize {
                            Text("Serving Size: \(normalizeServingSize(size))")
                                .font(.inter(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        if let count = servingsPerContainer {
                            let number = count.filter { $0.isNumber || $0 == "." }
                            Text("\(number.isEmpty ? count : number) servings per container")
                                .font(.inter(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        AvailabilityLabel(
                            availability: info.availability,
                            fallbackStation: station ?? "",
                            fallbackDiningHallName: diningHallName ?? "",
                            font: .subheadline,
                            iconFont: .caption,
                            forceColor: Color.umdRed
                        )
                    }
                    Spacer()
                    if let cal = calories {
                        VStack(spacing: 0) {
                            Text(cal)
                                .font(.inter(size: 44, weight: .bold))
                                .foregroundStyle(Color.umdRed)
                            Text("CALORIES")
                                .font(.inter(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .kerning(0.5)
                        }
                    }
                }
                .padding(16)
                .homeCard()
                .padding(.horizontal, 16)

                if info.nutrition.isEmpty || calories == nil {
                    Text("Nutrition unavailable")
                        .font(.inter(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    // Macros bar
                    macrosSection(info.nutrition)

                    // Similar foods dropdown
                    similarFoodsSection

                    // Full nutrition table
                    nutritionTable(info.nutrition)
                }

                // Allergens and Dietary (combined)
                if !info.dietaryIcons.isEmpty {
                    let allergenIcons = info.dietaryIcons.filter { DietaryStyles.isAllergen($0) }
                    let lifestyleIcons = info.dietaryIcons.filter { !DietaryStyles.isAllergen($0) }
                    let combinedIcons = allergenIcons + lifestyleIcons

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Allergens and Dietary")
                        FlowLayout(spacing: 4) {
                            ForEach(combinedIcons, id: \.self) { icon in
                                if DietaryStyles.isAllergen(icon) {
                                    DietaryTag(text: DietaryStyles.allergenAbbrev(for: icon))
                                } else {
                                    DietaryTag(text: DietaryStyles.dietaryShortLabel(for: icon),
                                               textColor: DietaryStyles.dietaryColor(for: icon),
                                               bgColor: DietaryStyles.dietaryBgColor(for: icon))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Ingredients
                if !info.ingredients.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Ingredients")
                        Text(info.ingredients)
                            .font(.inter(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .homeCard()
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.umdBackground)
    }

    private func macrosSection(_ nutrition: [String: String]) -> some View {
        HStack(spacing: 10) {
            macroItem(label: "Protein", value: nutritionValue("Protein", from: nutrition), color: .blue)
            macroItem(label: "Carbs", value: nutritionValue("Total Carbohydrate", from: nutrition), color: .green)
            macroItem(label: "Fat", value: nutritionValue("Total Fat", from: nutrition), color: .orange)
        }
        .padding(.horizontal, 16)
    }

    private func macroItem(label: String, value: String?, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value ?? "--")
                .font(.inter(size: 20, weight: .bold))
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(.inter(size: 11, weight: .bold))
                .foregroundStyle(color)
                .kerning(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .homeCard(tint: color)
    }

    private static let hallNames: [String: String] = [
        "19": "Yahentamitsi Dining Hall",
        "51": "251 North",
        "16": "South Campus Diner",
    ]

    private var isAvailableToday: Bool {
        if let a = viewModel.nutritionInfo?.availability {
            return a.availableToday
        }
        // If opened from a station on today's menu, it's available
        if station != nil { return true }
        guard let info = viewModel.nutritionInfo,
              let nextDate = info.nextAvailable else { return false }
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yyyy"
        guard let parsed = formatter.date(from: nextDate) else { return false }
        return Calendar.current.isDateInToday(parsed)
    }

    private var similarFoodsLabel: String {
        "Similar Foods"
    }

    private var similarFoodsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showSimilarFoods.toggle() }
            } label: {
                HStack {
                    Text(similarFoodsLabel)
                        .font(.inter(size: 15, weight: .semibold))
                    if viewModel.similarFoodsLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else if let foods = viewModel.similarFoods {
                        Text("(\(foods.count))")
                            .font(.inter(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: showSimilarFoods ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundStyle(Color.umdRed)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            if showSimilarFoods, let foods = viewModel.similarFoods, !foods.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(foods.enumerated()), id: \.element.id) { index, item in
                        let hallName = Self.hallNames[item.diningHallId] ?? ""
                        FoodItemRow(item: item, diningHallName: hallName, onTap: {
                            selectedSimilarItem = item
                        })
                            .matchedTransitionSource(id: "similar-\(item.recNum)", in: namespace)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            .animation(.easeOut(duration: 0.25).delay(Double(index) * 0.05), value: showSimilarFoods)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yyyy"
        return formatter.string(from: Date())
    }

    private func availabilityText(_ info: NutritionInfo) -> String {
        guard let nextDate = info.nextAvailable else {
            return "Unavailable this week"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yyyy"
        guard let parsed = formatter.date(from: nextDate) else {
            return "Unavailable this week"
        }
        if Calendar.current.isDateInToday(parsed) {
            return "Available today"
        }
        let display = DateFormatter()
        display.dateFormat = "EEE, MMM d"
        return "Next available \(display.string(from: parsed))"
    }

    private func nutritionTable(_ nutrition: [String: String]) -> some View {
        let visibleKey = keyNutrients.filter { nutritionValue($0, from: nutrition) != nil }
        let extraKeys = nutrition.keys.sorted().filter { key in
            let norm = normalizedKey(key).lowercased()
            let isExcluded = excludeFromTable.contains(where: { $0.lowercased() == norm })
            let isKey = keyNutrients.contains(where: { $0.lowercased() == norm })
            return !isExcluded && !isKey
        }

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Nutrition Facts")

            VStack(spacing: 0) {
                ForEach(visibleKey, id: \.self) { key in
                    if let value = nutritionValue(key, from: nutrition) {
                        nutritionRow(label: normalizedKey(key), value: value)
                    }
                }

                if !extraKeys.isEmpty {
                    Button {
                        withAnimation { showAllNutrition.toggle() }
                    } label: {
                        HStack {
                            Text(showAllNutrition ? "Show Less" : "Show All Nutrition")
                                .font(.inter(size: 14, weight: .semibold))
                            Spacer()
                            Image(systemName: showAllNutrition ? "chevron.up" : "chevron.down")
                                .font(.caption)
                        }
                        .foregroundStyle(Color.umdRed)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    if showAllNutrition {
                        ForEach(extraKeys, id: \.self) { key in
                            if let value = nutrition[key] {
                                nutritionRow(label: normalizedKey(key), value: value)
                            }
                        }
                    }
                }
            }
            .homeCard()
        }
        .padding(.horizontal, 16)
    }

    private func nutritionRow(label: String, value: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.inter(size: 14, weight: .medium))
                Spacer()
                Text(value)
                    .font(.inter(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider().padding(.leading, 16)
        }
    }

    private func nutritionValue(_ key: String, from nutrition: [String: String]) -> String? {
        let raw: String?
        if let v = nutrition[key] {
            raw = v
        } else {
            let normalized = key.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            raw = nutrition.first(where: {
                $0.key.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == normalized
            })?.value
        }
        guard let value = raw else { return nil }
        // Hide zero values like "0g", "0mg", "0.0mg"
        let digits = value.filter { $0.isNumber || $0 == "." }
        if let num = Double(digits), num == 0 { return nil }
        return value
    }

    private func normalizeServingSize(_ raw: String) -> String {
        // Split into number + unit, normalize the unit
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return trimmed }
        let number = String(parts[0])
        let unit = normalizeUnit(String(parts[1]))
        return "\(number) \(unit)"
    }

    private func normalizeUnit(_ raw: String) -> String {
        let lowered = raw.lowercased().trimmingCharacters(in: .whitespaces)
        switch lowered {
        case "oz", "oz.", "ounce", "ounces": return "oz"
        case "ea", "ea.", "each", "pc", "pcs", "piece", "pieces": return "ea"
        case "cup", "cups": return "cup"
        case "tbsp", "tablespoon", "tablespoons": return "tbsp"
        case "tsp", "teaspoon", "teaspoons": return "tsp"
        case "ml", "milliliter", "milliliters": return "ml"
        case "g", "gram", "grams": return "g"
        case "half": return "half"
        case "slice", "slices": return "slice"
        case "fl oz", "fluid oz": return "fl oz"
        default: return raw
        }
    }

    private func normalizedKey(_ key: String) -> String {
        key.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

}

#Preview {
    NavigationStack {
        NutritionDetailView(recNum: "12345", foodName: "Grilled Chicken Breast")
    }
    .environment(FavoritesManager.shared)
    .environment(NutritionTrackerManager.shared)
    .modelContainer(for: [DailyLog.self, TrackedEntry.self])
}

#Preview("With Mock Data") {
    NavigationStack {
        NutritionDetailView(recNum: "mock", foodName: "Chicken Congee")
    }
    .environment(FavoritesManager.shared)
    .environment(NutritionTrackerManager.shared)
    .modelContainer(for: [DailyLog.self, TrackedEntry.self])
}

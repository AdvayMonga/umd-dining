import Foundation
import SwiftUI

enum FeedRow: Identifiable {
    case stationHeader(station: String, diningHallId: String, isDiscovery: Bool)
    case menuItem(MenuItem)
    case seeMore

    var id: String {
        switch self {
        case .stationHeader(let s, let h, _): return "header_\(s)_\(h)"
        case .menuItem(let item): return "item_\(item.id)_\(item.station)_\(item.diningHallId)"
        case .seeMore: return "see_more"
        }
    }
}

@Observable
class HomeViewModel {
    var allItems: [MenuItem] = []
    var isLoading = false
    var errorMessage: String?
    var selectedMealPeriod: String = "Lunch"
    var selectedDate: Date = {
        let hour = Calendar.current.component(.hour, from: .now)
        if hour >= 22 {
            return Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        }
        return .now
    }()
    var selectedHallId: String {
        // Reconcile in the same mutation. Waiting for loadMenus() left one render with a meal the new
        // hall doesn't serve — an empty feed, which tore down the paged hall card mid-swipe.
        didSet { if selectedHallId != oldValue { reconcileMealPeriod() } }
    }

    let diningHallNames: [String: String] = [
        "19": "Yahentamitsi",
        "51": "251 North",
        "16": "South Campus Diner"
    ]

    let allHallIds = ["19", "51", "16"]

    init(selectedHallId: String) {
        self.selectedHallId = selectedHallId
    }
    let mealPeriods = ["Breakfast", "Brunch", "Lunch", "Dinner"]

    // Temporary session-only filters — defaults loaded from profile prefs
    var filterVegetarian: Bool = false
    var filterVegan: Bool = false
    var filterHalal: Bool = false
    var filterGlutenFree: Bool = false
    var filterDairyFree: Bool = false
    var filterHighProtein: Bool = false
    var filterAllergens: Set<String> = []

    var showDiscovery: Bool = false

    // Cache keys of network loads in flight — an empty menu isn't "closed" until they finish
    private var inFlightKeys: Set<String> = []
    // Cache key `allItems` was actually loaded for. Unlike lastLoadedKey, refreshes don't clear it.
    private var itemsKey: String?
    /// A load was cancelled before its items arrived. HomeView reloads when this turns on —
    /// a cancelled `.task` is often replaced anyway (tab reset), so no error is shown for it.
    private(set) var needsReload = false

    struct MenuRequest {
        let date: String
        let hallIds: [String]
        let vegetarian, vegan, halal, highProtein: Bool
        let allergens: Set<String>
    }

    /// The network fetch, swappable so tests can control timing
    @ObservationIgnored var fetchMenu: (MenuRequest) async throws -> [MenuItem] = { r in
        try await DiningAPIService.shared.fetchRankedMenu(
            date: r.date, diningHallIds: r.hallIds, userId: AuthManager.shared.userId,
            vegetarian: r.vegetarian, vegan: r.vegan, halal: r.halal,
            highProtein: r.highProtein, allergens: r.allergens
        )
    }

    // Cache: skip network call if same date + filters already loaded
    private var lastLoadedKey: String?
    private var hasLoadedPrefs = false

    var filtersMatchDefaults: Bool {
        let prefs = UserPreferences.shared
        return filterVegetarian == prefs.vegetarian
            && filterVegan == prefs.vegan
            && filterHalal == prefs.halal
            && filterGlutenFree == prefs.glutenFree
            && filterDairyFree == prefs.dairyFree
            && filterAllergens == prefs.allergens
            && !filterHighProtein
    }

    private var currentCacheKey: String {
        let allergenStr = filterAllergens.sorted().joined(separator: ",")
        let cuisinePrefs = UserPreferences.shared.cuisinePrefs.sorted().joined(separator: ",")
        let hallPrefs = UserPreferences.shared.preferredDiningHalls.sorted().joined(separator: ",")
        // v2: feeds cached by builds that still name-filtered condiments client-side must not be reused
        return "v2|\(dateString)|\(filterVegetarian)|\(filterVegan)|\(filterHalal)|\(filterGlutenFree)|\(filterDairyFree)|\(filterHighProtein)|\(allergenStr)|\(cuisinePrefs)|\(hallPrefs)"
    }

    // Snapshot of favorites at load time — keeps feed order stable until refresh
    private var loadedFavRecNums: Set<String> = []
    private var loadedFavStations: Set<String> = []

    var availableMealPeriods: [String] {
        availableMealPeriods(forHall: selectedHallId)
    }

    func availableMealPeriods(forHall hallId: String) -> [String] {
        let available = Set(allItems.filter { $0.diningHallId == hallId }.map(\.mealPeriod))
        let weekday = Calendar.current.component(.weekday, from: selectedDate)
        // Weekend Brunch stands in for Breakfast and Lunch, but only where a hall posts one —
        // halls that serve Breakfast/Lunch on weekends (251 North) must keep those tabs
        let brunchReplacesMeals = (weekday == 1 || weekday == 7) && available.contains("Brunch")
        return mealPeriods.filter { period in
            available.contains(period)
            && !(brunchReplacesMeals && (period == "Breakfast" || period == "Lunch"))
        }
    }


    private static let sideStationKeywords = [
        "sauce", "condiment", "dressing", "topping", "side dish", "sides",
        "beverage", "drink"
    ]

    private func isSideStation(_ name: String) -> Bool {
        let lower = name.lowercased()
        return Self.sideStationKeywords.contains { lower.contains($0) }
    }

    // Stations shown before "See More" when the API doesn't flag featured dishes
    private static let maxRecommendedStations = 5

    var displayRows: [FeedRow] {
        // Filter by meal + hall, excluding side stations (the server already drops condiments and toppings)
        let filtered = allItems.filter { item in
            item.mealPeriod == selectedMealPeriod
            && item.diningHallId == selectedHallId
            && !isSideStation(item.station)
        }

        // --- Build all unique stations in order (favored first) ---
        var allStations: [(station: String, hallId: String)] = []
        var seenKeys: Set<String> = []
        for item in filtered where seenKeys.insert("\(item.station)_\(item.diningHallId)").inserted {
            allStations.append((item.station, item.diningHallId))
        }
        // Favorite stations first; otherwise keep the server's order
        allStations = allStations.filter { loadedFavStations.contains($0.station) }
            + allStations.filter { !loadedFavStations.contains($0.station) }

        // Split into recommended and discovery. The server flags the dishes worth leading
        // with, so a strong menu spreads over more stations and a thin one over fewer.
        let usesFeatured = filtered.contains { $0.featured == true }
        let recommendedStations: [(station: String, hallId: String)]
        let discoveryStations: [(station: String, hallId: String)]
        if usesFeatured {
            let isFeatured: ((station: String, hallId: String)) -> Bool = { group in
                filtered.contains { $0.featured == true && $0.station == group.station && $0.diningHallId == group.hallId }
            }
            recommendedStations = allStations.filter(isFeatured)
            discoveryStations = allStations.filter { !isFeatured($0) }
        } else {
            let cap = Self.maxRecommendedStations
            recommendedStations = Array(allStations.prefix(cap))
            discoveryStations = Array(allStations.dropFirst(cap))
        }

        // --- Flatten to FeedRow ---
        var rows: [FeedRow] = []

        for group in recommendedStations {
            let stationItems = filtered.filter { $0.station == group.station && $0.diningHallId == group.hallId }
            guard !stationItems.isEmpty else { continue }
            rows.append(.stationHeader(station: group.station, diningHallId: group.hallId, isDiscovery: false))
            if usesFeatured && !showDiscovery {
                stationItems.filter { $0.featured == true }.forEach { rows.append(.menuItem($0)) }
            } else {
                // See More (or an API without featured flags): max 3 items per station, 4 for favorited stations
                let itemCap = loadedFavStations.contains(group.station) ? 4 : 3
                Array(stationItems.prefix(itemCap)).forEach { rows.append(.menuItem($0)) }
            }
        }

        if !discoveryStations.isEmpty {
            if showDiscovery {
                for group in discoveryStations {
                    let stationItems = filtered.filter { $0.station == group.station && $0.diningHallId == group.hallId }
                    guard !stationItems.isEmpty else { continue }
                    rows.append(.stationHeader(station: group.station, diningHallId: group.hallId, isDiscovery: true))
                    let itemCap = loadedFavStations.contains(group.station) ? 4 : 3
                    Array(stationItems.prefix(itemCap)).forEach { rows.append(.menuItem($0)) }
                }
            } else {
                rows.append(.seeMore)
            }
        }

        return rows
    }

    var activeFilterCount: Int {
        [filterVegetarian, filterVegan, filterHalal, filterGlutenFree, filterDairyFree, filterHighProtein]
            .filter { $0 }.count + filterAllergens.count
    }

    var hasActiveFilters: Bool { activeFilterCount > 0 }

    var menuState: HomeMenuState { menuState(rows: displayRows) }

    /// Takes rows the caller already built, so a render computes `displayRows` once
    func menuState(rows: [FeedRow]) -> HomeMenuState {
        HomeMenuState.resolve(
            isLoading: isLoading,
            // Only a load that's running (or owed after a cancel) counts. A key changed by the
            // filter overlay, with no load yet, resolves against the items on hand.
            isFetching: !inFlightKeys.isEmpty || needsReload || itemsKey == nil,
            errorMessage: errorMessage,
            hasRows: !rows.isEmpty,
            hallMeals: availableMealPeriods,
            anyHallHasItems: !allItems.isEmpty,
            selectedMeal: selectedMealPeriod,
            filtersActive: hasActiveFilters,
            schedule: DiningHallSchedule.all[selectedHallId],
            date: selectedDate
        )
    }

    /// Another hall with a menu for the selected day, for the empty state's "See …" button.
    /// Only halls whose selectable meals include a dish the feed shows (not just sides).
    var alternateHallWithMenu: String? {
        allHallIds.first { hallId in
            guard hallId != selectedHallId else { return false }
            let meals = Set(availableMealPeriods(forHall: hallId))
            return allItems.contains {
                $0.diningHallId == hallId && meals.contains($0.mealPeriod) && !isSideStation($0.station)
            }
        }
    }

    func diningHallName(for id: String) -> String {
        diningHallNames[id] ?? "Unknown"
    }

    func itemsForStation(station: String, hallId: String) -> [MenuItem] {
        allItems.filter { $0.station == station && $0.diningHallId == hallId }
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "M/d/yyyy"
        return f.string(from: selectedDate)
    }

    private var timeBasedMealPeriod: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 11 { return "Breakfast" }
        if hour < 16 { return "Lunch" }
        return "Dinner"
    }

    func autoSelectMealPeriod() {
        selectedMealPeriod = timeBasedMealPeriod
    }

    /// Keeps the selected meal period valid for the current hall and date.
    /// Halls don't all serve the same periods, so a period carried over from
    /// another hall can match nothing and render an empty menu.
    func reconcileMealPeriod() {
        let available = availableMealPeriods
        guard !available.isEmpty, !available.contains(selectedMealPeriod) else { return }
        selectedMealPeriod = available.contains(timeBasedMealPeriod) ? timeBasedMealPeriod : available[0]
    }

    private static let feedCacheKey = "cached_feed_data"
    private static let feedCacheKeyId = "cached_feed_key"

    private func loadFromDisk() {
        guard let keyId = UserDefaults.standard.string(forKey: Self.feedCacheKeyId),
              keyId == currentCacheKey,
              let data = UserDefaults.standard.data(forKey: Self.feedCacheKey),
              let items = try? JSONDecoder().decode([MenuItem].self, from: data)
        else { return }
        allItems = items
        lastLoadedKey = keyId
    }

    private func saveToDisk(key: String) {
        guard let data = try? JSONEncoder().encode(allItems) else { return }
        UserDefaults.standard.set(data, forKey: Self.feedCacheKey)
        UserDefaults.standard.set(key, forKey: Self.feedCacheKeyId)
    }

    func loadMenus() async {
        // Sync temp filters from saved profile preferences (once per session). Must run before the
        // cache check: a launch served from disk returns early below, and syncing on a later load
        // would overwrite the filter the user just applied.
        if !hasLoadedPrefs {
            let prefs = UserPreferences.shared
            filterVegetarian = prefs.vegetarian
            filterVegan = prefs.vegan
            filterHalal = prefs.halal
            filterGlutenFree = prefs.glutenFree
            filterDairyFree = prefs.dairyFree
            filterAllergens = prefs.allergens
            hasLoadedPrefs = true
        }

        // Try disk cache first (instant app launch)
        if allItems.isEmpty {
            loadFromDisk()
        }

        // Skip network if same date + filters already loaded. The fetch covers
        // every hall, so switching halls lands here — the selected meal period
        // still has to be re-checked against the new hall's offerings.
        guard lastLoadedKey != currentCacheKey else {
            itemsKey = lastLoadedKey
            needsReload = false
            reconcileMealPeriod()
            return
        }

        // Capture the request before awaiting: date and filters can change while it's in flight
        let requestKey = currentCacheKey
        // Hall swipes during a load would otherwise fetch the same menu again
        guard !inFlightKeys.contains(requestKey) else { return }
        var effectiveAllergens = filterAllergens
        if filterGlutenFree { effectiveAllergens.insert("Contains gluten") }
        if filterDairyFree { effectiveAllergens.insert("Contains dairy") }
        let request = MenuRequest(
            date: dateString, hallIds: allHallIds,
            vegetarian: filterVegetarian, vegan: filterVegan, halal: filterHalal,
            highProtein: filterHighProtein, allergens: effectiveAllergens
        )
        let saveAfterLoad = filtersMatchDefaults

        isLoading = allItems.isEmpty  // Only show spinner if no cached data
        errorMessage = nil
        needsReload = false
        inFlightKeys.insert(requestKey)
        defer { inFlightKeys.remove(requestKey) }
        showDiscovery = false

        // Snapshot favorites at load time so feed order stays stable until next refresh
        loadedFavRecNums = Set(FavoritesManager.shared.favoriteFoods.keys)
        loadedFavStations = FavoritesManager.shared.favoriteStations

        do {
            let items = try await fetchMenu(request)
            // A newer date or filter set took over while this was in flight; its own load applies
            guard requestKey == currentCacheKey else { isLoading = false; return }
            allItems = items
            lastLoadedKey = requestKey
            itemsKey = requestKey
            if saveAfterLoad {
                saveToDisk(key: requestKey)
            }
            reconcileMealPeriod()
        } catch {
            if error is CancellationError || Task.isCancelled {
                // Owe a reload only if this key's items never arrived and nothing newer replaced it
                if itemsKey != requestKey && requestKey == currentCacheKey { needsReload = true }
            } else if requestKey == currentCacheKey {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    func forceReloadMenus() async {
        lastLoadedKey = nil
        hasLoadedPrefs = false
        await loadMenus()
    }

    func syncPrefsAndReloadIfNeeded() async {
        // Sync profile prefs into session filters
        let prefs = UserPreferences.shared
        filterVegetarian = prefs.vegetarian
        filterVegan = prefs.vegan
        filterHalal = prefs.halal
        filterGlutenFree = prefs.glutenFree
        filterDairyFree = prefs.dairyFree
        filterAllergens = prefs.allergens

        // Check if favorites changed since last load
        let currentFavFoods = Set(FavoritesManager.shared.favoriteFoods.keys)
        let currentFavStations = FavoritesManager.shared.favoriteStations
        let favsChanged = currentFavFoods != loadedFavRecNums || currentFavStations != loadedFavStations

        if favsChanged {
            loadedFavRecNums = currentFavFoods
            loadedFavStations = currentFavStations
            lastLoadedKey = nil  // Force re-fetch since favorites affect ranking
        }

        // Re-fetch if cache key changed (prefs/filters/cuisine) or favorites changed
        await loadMenus()
    }
}

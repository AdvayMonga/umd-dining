import Foundation

/// What Home shows below the hall card. Pure so the empty-state decision and wording are testable.
enum HomeMenuState: Equatable {
    case loading
    case error(String)
    case menu
    /// This hall has nothing for the day while other halls do — almost always a closure (breaks, holidays)
    case hallNotServing(filtered: Bool)
    /// No hall has anything for the day — menus not posted yet, or a campus-wide closure
    case noMenusPosted(filtered: Bool)
    /// The hall serves other meals that day, just not this one
    case mealNotServed(meal: String, nextMeal: String?, nextOpens: String?)
    /// The meal is posted, but only drinks and sides — the feed hides those stations
    case sidesOnly(meal: String)

    private static let mealOrder = ["Breakfast", "Brunch", "Lunch", "Dinner"]

    static func resolve(
        isLoading: Bool,
        isFetching: Bool,
        errorMessage: String?,
        hasRows: Bool,
        hallMeals: [String],
        anyHallHasItems: Bool,
        selectedMeal: String,
        filtersActive: Bool,
        schedule: DiningHallSchedule? = nil,
        date: Date = .now
    ) -> HomeMenuState {
        if isLoading { return .loading }
        if let errorMessage { return .error(errorMessage) }
        // A fetch in flight could still fill an empty menu, so it isn't "closed" yet
        if isFetching && !hasRows { return .loading }
        if hasRows { return .menu }
        guard !hallMeals.isEmpty else {
            return anyHallHasItems ? .hallNotServing(filtered: filtersActive) : .noMenusPosted(filtered: filtersActive)
        }
        // The selected meal has items, they just aren't shown — don't claim it isn't served
        if hallMeals.contains(selectedMeal) { return .sidesOnly(meal: selectedMeal) }
        // Prefer the next meal of the day; fall back to an earlier one
        let selectedIndex = mealOrder.firstIndex(of: selectedMeal) ?? -1
        let others = hallMeals.filter { $0 != selectedMeal }
        let next = others.first { (mealOrder.firstIndex(of: $0) ?? 0) > selectedIndex } ?? others.first
        let opens = next.flatMap { meal in
            schedule?.windows(on: date).first { $0.name == meal }?.openTimeString
        }
        return .mealNotServed(meal: selectedMeal, nextMeal: next, nextOpens: opens)
    }

    /// "today", "tomorrow" or "on Saturday"
    static func dayPhrase(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) { return "tomorrow" }
        return "on \(date.formatted(.dateTime.weekday(.wide)))"
    }

    /// Headline and supporting line for the empty states. `closedReason` (e.g. from live hours)
    /// replaces the generic explanation when the hall or campus is closed.
    func copy(hallName: String, date: Date, now: Date = .now, closedReason: String? = nil) -> (title: String, message: String) {
        let day = Self.dayPhrase(for: date, now: now)
        switch self {
        case .hallNotServing(false):
            return ("\(hallName) isn't serving \(day)",
                    closedReason ?? "No menu is posted, so it's likely closed. Swipe the card above to check another hall.")
        case .hallNotServing(true):
            return ("Nothing at \(hallName) \(day)",
                    closedReason ?? "It may be closed, or nothing matches your filters.")
        case .noMenusPosted(false):
            return ("No menus posted \(day)",
                    closedReason ?? "UMD Dining hasn't posted menus for this day yet. Try another day or check the hours.")
        case .noMenusPosted(true):
            // Filters apply server-side, so an empty answer can't tell "closed" from "filtered out"
            return ("No menus to show \(day)",
                    closedReason ?? "Dining halls may be closed, or nothing matches your filters.")
        case .mealNotServed(let meal, let next, let opens):
            let title = "No \(meal.lowercased()) \(day)"
            guard let next else { return (title, "No menu is posted for this meal.") }
            if let opens { return (title, "\(next) starts at \(opens).") }
            return (title, "\(next) is on the menu.")
        case .sidesOnly(let meal):
            return ("Only sides for \(meal.lowercased()) \(day)",
                    "Just drinks and sides are posted for \(meal.lowercased()) so far.")
        case .loading, .error, .menu:
            return ("", "")
        }
    }
}

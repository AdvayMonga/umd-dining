import Testing
import Foundation
@testable import UMD_Dining

private func day(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
    var c = DateComponents(); c.year = 2026; c.month = month; c.day = day; c.hour = hour
    return Calendar.current.date(from: c)!
}

/// Defaults describe a settled load with nothing for the selected hall, so each test states only what differs.
private func resolve(
    isLoading: Bool = false,
    isFetching: Bool = false,
    errorMessage: String? = nil,
    hasRows: Bool = false,
    hallMeals: [String] = [],
    anyHallHasItems: Bool = true,
    selectedMeal: String = "Lunch",
    filtersActive: Bool = false,
    schedule: DiningHallSchedule? = nil,
    date: Date = day(10, 13)
) -> HomeMenuState {
    HomeMenuState.resolve(
        isLoading: isLoading, isFetching: isFetching, errorMessage: errorMessage,
        hasRows: hasRows, hallMeals: hallMeals, anyHallHasItems: anyHallHasItems,
        selectedMeal: selectedMeal, filtersActive: filtersActive, schedule: schedule, date: date
    )
}

struct HomeMenuStateDecisionTests {

    /// Fall break 2026: Yahentamitsi posted nothing Oct 10–12 while 251 North and South Campus served.
    @Test func hallWithNothingWhileOthersServeIsClosed() {
        #expect(resolve(hallMeals: [], anyHallHasItems: true) == .hallNotServing(filtered: false))
    }

    @Test func noHallWithAMenuMeansNothingPosted() {
        #expect(resolve(hallMeals: [], anyHallHasItems: false) == .noMenusPosted(filtered: false))
    }

    /// Filters can empty a hall too, so the copy mustn't claim it's closed
    @Test func activeFiltersAreCarriedIntoTheEmptyState() {
        #expect(resolve(filtersActive: true) == .hallNotServing(filtered: true))
        #expect(resolve(anyHallHasItems: false, filtersActive: true) == .noMenusPosted(filtered: true))
    }

    @Test func loadingWinsOverEverything() {
        #expect(resolve(isLoading: true, errorMessage: "offline", hasRows: true) == .loading)
    }

    /// An in-flight fetch could still fill an empty feed — don't flash "closed" while switching days
    @Test func emptyFeedDuringAFetchIsLoadingNotClosed() {
        #expect(resolve(isFetching: true) == .loading)
    }

    /// A background refresh shouldn't hide a menu that's already on screen
    @Test func rowsStayVisibleDuringARefresh() {
        #expect(resolve(isFetching: true, hasRows: true) == .menu)
    }

    @Test func errorIsDistinctFromClosed() {
        #expect(resolve(errorMessage: "The Internet connection appears to be offline.")
                == .error("The Internet connection appears to be offline."))
        // A failed first load leaves nothing in flight but must still surface the error
        #expect(resolve(isFetching: true, errorMessage: "timeout") == .error("timeout"))
    }

    @Test func rowsMeanMenu() {
        #expect(resolve(hasRows: true, hallMeals: ["Lunch"]) == .menu)
    }

    /// "No lunch today — dinner starts at 4 PM"
    @Test func missingMealPointsToTheNextOneWithItsUsualStart() {
        let schedule = DiningHallSchedule.all["19"]
        let state = resolve(hallMeals: ["Dinner"], selectedMeal: "Lunch", schedule: schedule, date: day(10, 13))
        #expect(state == .mealNotServed(meal: "Lunch", nextMeal: "Dinner", nextOpens: "4 PM"))
    }

    @Test func missingMealFallsBackToAnEarlierOne() {
        let state = resolve(hallMeals: ["Brunch"], selectedMeal: "Dinner")
        #expect(state == .mealNotServed(meal: "Dinner", nextMeal: "Brunch", nextOpens: nil))
    }

    /// The meal has items but the feed hides them all (drinks, sauces) — not "no dinner"
    @Test func selectedMealWithNoShownRowsIsSidesOnly() {
        #expect(resolve(hallMeals: ["Lunch", "Dinner"], selectedMeal: "Dinner") == .sidesOnly(meal: "Dinner"))
    }
}

struct HomeMenuStateCopyTests {

    private let now = day(10, 11, hour: 9)   // Sunday, Oct 11 2026

    @Test func closedHallNamesTheHallAndDay() {
        let today = HomeMenuState.hallNotServing(filtered: false).copy(hallName: "Yahentamitsi", date: day(10, 11), now: now)
        #expect(today.title == "Yahentamitsi isn't serving today")
        let monday = HomeMenuState.hallNotServing(filtered: false).copy(hallName: "Yahentamitsi", date: day(10, 12), now: now)
        #expect(monday.title == "Yahentamitsi isn't serving tomorrow")
        let saturday = HomeMenuState.hallNotServing(filtered: false).copy(hallName: "Yahentamitsi", date: day(10, 10), now: now)
        #expect(saturday.title == "Yahentamitsi isn't serving on Saturday")
    }

    @Test func mealCopyReadsNaturally() {
        let copy = HomeMenuState.mealNotServed(meal: "Lunch", nextMeal: "Dinner", nextOpens: "4 PM")
            .copy(hallName: "Yahentamitsi", date: day(10, 11), now: now)
        #expect(copy.title == "No lunch today")
        #expect(copy.message == "Dinner starts at 4 PM.")
    }

    /// The live-hours seam: a specific reason replaces the generic guess
    @Test func closedReasonReplacesTheGenericMessage() {
        let copy = HomeMenuState.hallNotServing(filtered: false)
            .copy(hallName: "Yahentamitsi", date: day(10, 11), now: now, closedReason: "Closed for fall break")
        #expect(copy.message == "Closed for fall break")
    }

    @Test func sidesOnlyCopyDoesNotContradictTheSelectedTab() {
        let copy = HomeMenuState.sidesOnly(meal: "Dinner").copy(hallName: "Yahentamitsi", date: day(10, 11), now: now)
        #expect(copy.title == "Only sides for dinner today")
        #expect(!copy.title.contains("No dinner"))
    }

    @Test func filteredCopyDoesNotClaimTheHallIsClosed() {
        let copy = HomeMenuState.hallNotServing(filtered: true).copy(hallName: "251 North", date: day(10, 11), now: now)
        #expect(!copy.title.contains("isn't serving"))
        #expect(copy.message.contains("filters"))
    }

    /// Filters apply server-side, so an empty campus could be closed or filtered out — say both
    @Test func filteredNoMenusCopyCoversClosedAndFiltered() {
        let copy = HomeMenuState.noMenusPosted(filtered: true).copy(hallName: "251 North", date: day(10, 11), now: now)
        #expect(copy.title == "No menus to show today")
        #expect(copy.message == "Dining halls may be closed, or nothing matches your filters.")
    }
}

struct ScheduleWindowsTests {

    @Test func fridayUsesItsOwnWindowsWhenDefined() {
        let north = DiningHallSchedule.all["51"]!
        #expect(north.windows(on: day(10, 16)).last?.closeTimeString == "7 PM")   // Friday
        #expect(north.windows(on: day(10, 15)).last?.closeTimeString == "10 PM")  // Thursday
    }

    @Test func weekendsUseWeekendWindows() {
        let yahentamitsi = DiningHallSchedule.all["19"]!
        #expect(yahentamitsi.windows(on: day(10, 11)).map(\.name) == ["Brunch", "Dinner"])
    }
}

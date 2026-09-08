import Testing
import Foundation
@testable import UMD_Dining

/// MenuItem only has a decoding initializer, so fixtures come from JSON —
/// which also keeps the API response contract under test.
private func menuItem(
    recNum: String = "1",
    name: String = "Test Food",
    hall: String = "19",
    meal: String = "Lunch",
    station: String = "Grill",
    date: String = "9/5/2026",
    icons: [String] = []
) -> MenuItem {
    let json = """
    {
      "name": "\(name)",
      "rec_num": "\(recNum)",
      "dining_hall_id": "\(hall)",
      "date": "\(date)",
      "meal_period": "\(meal)",
      "station": "\(station)",
      "dietary_icons": [\(icons.map { "\"\($0)\"" }.joined(separator: ","))],
      "nutrition_fetched": true,
      "tags": []
    }
    """
    return try! JSONDecoder().decode(MenuItem.self, from: Data(json.utf8))
}

/// A Thursday — weekday rules keep Breakfast and Lunch available.
private let weekday: Date = {
    var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 3
    return Calendar.current.date(from: c)!
}()

/// A Saturday — availableMealPeriods drops Breakfast and Lunch.
private let weekend: Date = {
    var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 5
    return Calendar.current.date(from: c)!
}()

@MainActor
struct MealPeriodReconciliationTests {

    /// Regression: the menu request covers every hall, so switching halls
    /// doesn't change the cache key and loadMenus() returns early. Before the
    /// fix that skipped this correction, leaving a meal period the new hall
    /// doesn't serve — and the menu rendered empty.
    @Test func switchingToAHallWithoutTheSelectedMealSnapsToAnAvailableOne() {
        let vm = HomeViewModel(selectedHallId: "19")
        vm.selectedDate = weekday
        vm.allItems = [
            menuItem(recNum: "1", hall: "19", meal: "Lunch"),
            menuItem(recNum: "2", hall: "51", meal: "Dinner"),
        ]
        vm.selectedMealPeriod = "Lunch"

        vm.selectedHallId = "51"   // 251 North has no Lunch in this fixture
        vm.reconcileMealPeriod()

        #expect(vm.selectedMealPeriod == "Dinner")
        #expect(!vm.displayRows.isEmpty, "a hall with items must never render an empty menu")
    }

    /// The invariant that matters, independent of what time the suite runs.
    @Test func selectionIsAlwaysValidForTheCurrentHallAfterReconciling() {
        for hall in ["19", "51", "16"] {
            let vm = HomeViewModel(selectedHallId: hall)
            vm.selectedDate = weekday
            vm.allItems = [
                menuItem(recNum: "1", hall: "19", meal: "Breakfast"),
                menuItem(recNum: "2", hall: "51", meal: "Dinner"),
                menuItem(recNum: "3", hall: "16", meal: "Lunch"),
            ]
            vm.selectedMealPeriod = "Brunch"   // offered by none of them
            vm.reconcileMealPeriod()
            #expect(vm.availableMealPeriods.contains(vm.selectedMealPeriod))
        }
    }

    @Test func aValidSelectionIsLeftAlone() {
        let vm = HomeViewModel(selectedHallId: "19")
        vm.selectedDate = weekday
        vm.allItems = [
            menuItem(recNum: "1", hall: "19", meal: "Breakfast"),
            menuItem(recNum: "2", hall: "19", meal: "Dinner"),
        ]
        vm.selectedMealPeriod = "Dinner"
        vm.reconcileMealPeriod()
        #expect(vm.selectedMealPeriod == "Dinner")
    }

    @Test func hallWithNoItemsLeavesSelectionUntouched() {
        let vm = HomeViewModel(selectedHallId: "16")
        vm.selectedDate = weekday
        vm.allItems = [menuItem(recNum: "1", hall: "19", meal: "Lunch")]
        vm.selectedMealPeriod = "Lunch"
        vm.reconcileMealPeriod()
        #expect(vm.selectedMealPeriod == "Lunch")   // nothing better to offer
    }

    @Test func weekendBrunchIsChosenOverExcludedWeekdayPeriods() {
        let vm = HomeViewModel(selectedHallId: "19")
        vm.selectedDate = weekend
        vm.allItems = [
            menuItem(recNum: "1", hall: "19", meal: "Brunch", date: "9/5/2026"),
            menuItem(recNum: "2", hall: "19", meal: "Lunch", date: "9/5/2026"),
        ]
        vm.selectedMealPeriod = "Lunch"   // excluded on weekends
        vm.reconcileMealPeriod()
        #expect(vm.selectedMealPeriod == "Brunch")
    }
}

@MainActor
struct AvailableMealPeriodsTests {

    @Test func onlyPeriodsTheSelectedHallServes() {
        let vm = HomeViewModel(selectedHallId: "19")
        vm.selectedDate = weekday
        vm.allItems = [
            menuItem(recNum: "1", hall: "19", meal: "Lunch"),
            menuItem(recNum: "2", hall: "51", meal: "Dinner"),
        ]
        #expect(vm.availableMealPeriods == ["Lunch"])
    }

    @Test func weekendsExcludeBreakfastAndLunch() {
        let vm = HomeViewModel(selectedHallId: "19")
        vm.selectedDate = weekend
        vm.allItems = [
            menuItem(recNum: "1", hall: "19", meal: "Breakfast", date: "9/5/2026"),
            menuItem(recNum: "2", hall: "19", meal: "Lunch", date: "9/5/2026"),
            menuItem(recNum: "3", hall: "19", meal: "Brunch", date: "9/5/2026"),
            menuItem(recNum: "4", hall: "19", meal: "Dinner", date: "9/5/2026"),
        ]
        #expect(vm.availableMealPeriods == ["Brunch", "Dinner"])
    }

    @Test func orderFollowsTheDaysProgression() {
        let vm = HomeViewModel(selectedHallId: "19")
        vm.selectedDate = weekday
        vm.allItems = [
            menuItem(recNum: "1", hall: "19", meal: "Dinner"),
            menuItem(recNum: "2", hall: "19", meal: "Breakfast"),
        ]
        #expect(vm.availableMealPeriods == ["Breakfast", "Dinner"])
    }

    @Test func noItemsMeansNoPeriods() {
        let vm = HomeViewModel(selectedHallId: "19")
        vm.selectedDate = weekday
        #expect(vm.availableMealPeriods.isEmpty)
    }
}

@MainActor
struct FeedFilteringTests {

    @Test func onlyTheSelectedHallAndMealAppear() {
        let vm = HomeViewModel(selectedHallId: "19")
        vm.selectedDate = weekday
        vm.selectedMealPeriod = "Lunch"
        vm.allItems = [
            menuItem(recNum: "keep", hall: "19", meal: "Lunch"),
            menuItem(recNum: "otherHall", hall: "51", meal: "Lunch"),
            menuItem(recNum: "otherMeal", hall: "19", meal: "Dinner"),
        ]
        let shown = vm.displayRows.compactMap { row -> String? in
            if case .menuItem(let item) = row { return item.recNum }
            return nil
        }
        #expect(shown.contains("keep"))
        #expect(!shown.contains("otherHall"))
        #expect(!shown.contains("otherMeal"))
    }

    @Test func stationHeadersAccompanyTheirItems() {
        let vm = HomeViewModel(selectedHallId: "19")
        vm.selectedDate = weekday
        vm.selectedMealPeriod = "Lunch"
        vm.allItems = [menuItem(recNum: "1", hall: "19", meal: "Lunch", station: "Grill")]
        let headers = vm.displayRows.compactMap { row -> String? in
            if case .stationHeader(let station, _, _) = row { return station }
            return nil
        }
        #expect(headers.contains("Grill"))
    }
}

struct MenuItemDecodingTests {

    @Test func decodesTheApiSnakeCaseContract() {
        let item = menuItem(recNum: "42", name: "Chicken Tikka", hall: "51",
                            meal: "Dinner", station: "Global Kitchen", icons: ["vegan"])
        #expect(item.recNum == "42")
        #expect(item.name == "Chicken Tikka")
        #expect(item.diningHallId == "51")
        #expect(item.mealPeriod == "Dinner")
        #expect(item.station == "Global Kitchen")
        #expect(item.dietaryIcons == ["vegan"])
        #expect(item.id == "42")
    }

    @Test func optionalFieldsToleratedWhenAbsent() {
        let item = menuItem()
        #expect(item.allergens == nil)
        #expect(item.nutrition == nil)
        #expect(item.tags.isEmpty)
    }
}

import Testing
import Foundation
@testable import UMD_Dining

/// Campus calendar so the tests don't depend on the simulator's time zone.
private let campus: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/New_York")!
    cal.locale = Locale(identifier: "en_US")
    return cal
}()

private func at(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    campus.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

/// Fall break 2026 as /api/hours returns it: Yahentamitsi closed 10/10–10/12,
/// dinner only 10/13, full day 10/14. 251 North has a summer-style gap on 10/12.
private let json = """
{
  "success": true, "start": "2026-10-10", "days": 5,
  "source": "https://dining.umd.edu/hours/open-now", "fetched_at": "2026-10-10T12:00:00+00:00",
  "halls": {
    "19": {
      "2026-10-10": [], "2026-10-11": [], "2026-10-12": [],
      "2026-10-13": [{"meal": "Dinner", "open": "16:00", "close": "21:00"}],
      "2026-10-14": [{"meal": "Lunch", "open": "10:30", "close": "16:00"},
                     {"meal": "Breakfast", "open": "07:00", "close": "10:30"},
                     {"meal": "Dinner", "open": "16:00", "close": "21:00"}]
    },
    "51": {
      "2026-10-12": [{"meal": "Lunch", "open": "11:00", "close": "13:30"},
                     {"meal": "Dinner", "open": "17:00", "close": "19:00"}],
      "2026-10-13": [{"meal": "Dinner", "open": "bogus", "close": "21:00"}]
    }
  }
}
"""

private func liveDays() throws -> [String: [String: [MealWindow]]] {
    try JSONDecoder().decode(HallHoursResponse.self, from: Data(json.utf8)).mealWindows
}

private func status(_ hall: String, _ date: Date) throws -> DiningHallSchedule.Status? {
    DiningHallSchedule.status(days: try liveDays()[hall] ?? [:], at: date, calendar: campus)
}

struct HallHoursDecodingTests {

    @Test func decodesWindowsSortedByOpenTime() throws {
        let days = try liveDays()
        #expect(days["19"]?["2026-10-10"]?.isEmpty == true)
        #expect(days["19"]?["2026-10-14"]?.map(\.name) == ["Breakfast", "Lunch", "Dinner"])
        let dinner = try #require(days["19"]?["2026-10-13"]?.first)
        #expect(dinner.openMinute == 16 * 60 && dinner.closeMinute == 21 * 60)
    }

    @Test func aDateWithOnlyUnparseableWindowsIsUnknownNotClosed() throws {
        #expect(try liveDays()["51"]?["2026-10-13"] == nil)
    }

    @Test func parsesHourMinuteStrings() {
        #expect(HallHoursResponse.minutes("07:30") == 450)
        #expect(HallHoursResponse.minutes("24:00") == 1440)
        #expect(HallHoursResponse.minutes("7pm") == nil)
        #expect(HallHoursResponse.minutes("25:00") == nil)
    }
}

struct HallHoursStatusTests {

    @Test func closedDayLooksAheadToTheNextOpening() throws {
        let s = try #require(try status("19", at(10, 11, 12)))
        #expect(!s.isOpen && s.currentMeal == nil)
        #expect(s.nextMeal == "Dinner" && s.nextOpenTime == "4 PM" && s.nextOpenDay == "Tue")
    }

    @Test func nextOpeningTomorrowSaysTomorrow() throws {
        let s = try #require(try status("19", at(10, 12, 20)))
        #expect(s.nextOpenDay == "tomorrow" && s.nextOpenTime == "4 PM")
    }

    @Test func dinnerOnlyDayIsClosedUntilDinnerThenOpen() throws {
        let morning = try #require(try status("19", at(10, 13, 9)))
        #expect(!morning.isOpen && morning.nextOpenTime == "4 PM" && morning.nextOpenDay == nil)
        let evening = try #require(try status("19", at(10, 13, 18)))
        #expect(evening.isOpen && evening.currentMeal == "Dinner" && evening.dayCloseTime == "9 PM")
        #expect(!evening.isClosingSoon)
    }

    @Test func backToBackMealsStayOpenUntilTheDayCloses() throws {
        let s = try #require(try status("19", at(10, 14, 11)))
        #expect(s.isOpen && s.currentMeal == "Lunch" && s.dayCloseTime == "9 PM" && !s.isClosingSoon)
    }

    @Test func closingSoonInTheLastHalfHour() throws {
        #expect(try status("19", at(10, 14, 20, 40))?.isClosingSoon == true)
        #expect(try status("19", at(10, 14, 20, 20))?.isClosingSoon == false)
    }

    @Test func betweenMealsShowsTheNextMealToday() throws {
        let gap = try #require(try status("51", at(10, 12, 15)))
        #expect(!gap.isOpen && gap.nextMeal == "Dinner" && gap.nextOpenTime == "5 PM" && gap.nextOpenDay == nil)
        // A gap after lunch means the hall closes at 1:30, not at dinner's close
        let lunch = try #require(try status("51", at(10, 12, 13, 10)))
        #expect(lunch.isOpen && lunch.dayCloseTime == "1:30 PM" && lunch.isClosingSoon)
    }

    @Test func lookAheadStopsWhereTheDataEnds() throws {
        let s = try #require(try status("19", at(10, 14, 22)))
        #expect(!s.isOpen && s.nextOpenTime == nil && s.nextOpenDay == nil)
    }

    @Test func dayMissingFromTheDataReturnsNil() throws {
        #expect(try status("19", at(10, 20, 12)) == nil)
    }
}

@MainActor
struct HallHoursServiceTests {

    private func freshDefaults() -> UserDefaults {
        let name = "HallHoursTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func fallsBackToHardcodedScheduleWithoutLiveData() {
        let service = HallHoursService(defaults: freshDefaults())
        let date = at(10, 11, 12)
        let expected = DiningHallSchedule.all["19"]!.currentStatus(at: date)
        let s = service.status(for: "19", at: date)
        #expect(s.isOpen == expected.isOpen && s.currentMeal == expected.currentMeal)
    }

    @Test func liveDataOverridesAndSurvivesRelaunch() throws {
        let defaults = freshDefaults()
        let response = try JSONDecoder().decode(HallHoursResponse.self, from: Data(json.utf8))
        HallHoursService(defaults: defaults).apply(response)

        let relaunched = HallHoursService(defaults: defaults)   // reads the offline copy
        #expect(!relaunched.status(for: "19", at: at(10, 11, 12)).isOpen)
        // 16 isn't in the live data at all -> hardcoded
        let date = at(10, 11, 12)
        #expect(relaunched.status(for: "16", at: date).isOpen == DiningHallSchedule.all["16"]!.currentStatus(at: date).isOpen)
    }
}

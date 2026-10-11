import Testing
import Foundation
@testable import UMD_Dining

@MainActor
struct GuestPassTests {
    private func date(_ weekday: Int, _ hour: Int, _ minute: Int) -> Date {
        // 2026-10-05 is a Monday; weekday 2 = Monday in Calendar terms
        var comps = DateComponents(year: 2026, month: 10, day: 5 + (weekday - 2), hour: hour, minute: minute)
        comps.second = 37
        return Calendar.current.date(from: comps)!
    }

    @Test func slotsLandOnTheHalfHourWhileOpen() {
        let yahentamitsi = GuestPassHall.find("19")   // Mon–Thu 7:00–21:00
        let slots = GuestPassTiming.slots(for: yahentamitsi, from: date(2, 12, 10))
        #expect(slots.count == 8)
        for slot in slots {
            #expect([0, 30].contains(Calendar.current.component(.minute, from: slot)))
            #expect(Calendar.current.component(.second, from: slot) == 0)
        }
        #expect(Calendar.current.component(.hour, from: slots[0]) == 12)
        #expect(Calendar.current.component(.minute, from: slots[0]) == 30)
    }

    @Test func noSlotsAfterClose() {
        let yahentamitsi = GuestPassHall.find("19")
        let late = GuestPassTiming.slots(for: yahentamitsi, from: date(2, 20, 15))
        // Only 20:30 is still before the 21:00 close
        #expect(late.count == 1)
    }

    @Test func pricesFollowDoorPricesByMeal() {
        // 30% under UMD's door prices, rounded to whole dollars
        #expect(GuestPassPricing.buyerPrice("Breakfast") == 7)   // $9.50 at the door
        #expect(GuestPassPricing.buyerPrice("Lunch") == 11)      // $16.25
        #expect(GuestPassPricing.buyerPrice("Dinner") == 14)     // $20.25
        #expect(GuestPassPricing.buyerPrice("Brunch") == GuestPassPricing.buyerPrice("Lunch"))
        #expect(GuestPassPricing.holderEarns("Dinner") < GuestPassPricing.buyerPrice("Dinner"))
    }

    @Test func mealComesFromTheHallSchedule() {
        let hall = GuestPassHall.find("19")
        #expect(GuestPassPricing.meal(at: hall, date(2, 8, 0)) == "Breakfast")
        #expect(GuestPassPricing.meal(at: hall, date(2, 12, 0)) == "Lunch")
        #expect(GuestPassPricing.meal(at: hall, date(2, 18, 0)) == "Dinner")
    }

    @Test func thanksgivingClosesEveryHall() {
        let thanksgiving = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 12))!
        for hall in GuestPassHall.all {
            #expect(!hall.isOpen(at: thanksgiving))
        }
        #expect(DiningSpecialHours.period(at: thanksgiving)?.closed == true)
    }

    @Test func swipeCompletesAndUsesAPass() async throws {
        let store = GuestPassStore()
        let before = store.passesLeft
        let request = try #require(store.visibleRequests.first)
        store.accept(request)
        let job = try #require(store.jobs.first)
        store.swipedIn(job)
        try await Task.sleep(for: .seconds(2.5))
        #expect(store.passesLeft == before - 1)
        #expect(store.jobs.first?.step == .rate)
    }
}

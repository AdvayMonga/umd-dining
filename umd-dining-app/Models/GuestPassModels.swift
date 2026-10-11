import Foundation

// MARK: - Rules & pricing

enum GuestPassRules {
    /// UNCONFIRMED: whether the pass holder has to walk in with the guest or can
    /// swipe them in and leave. Flip once checked at a dining hall; copy follows.
    static let holderMustEnter = false

    /// How long either side waits at the door before they can report a no-show
    static let noShowAfterMinutes = 10
    /// How long a "now" request waits for a holder
    static let matchTimeout: TimeInterval = 5 * 60

    /// Guest passes included per semester by resident plan (Fall 2026 / Spring 2027)
    static let passesByPlan: [(plan: String, passes: Int)] = [
        ("Base", 2), ("Base Plus", 4), ("Preferred", 6), ("Premium", 8),
    ]
}

/// One price per meal, the same at every hall, pegged to UMD's door prices
enum GuestPassPricing {
    /// UMD Dining walk-in prices, Fall 2026 (dining.umd.edu → Dining Halls → Door Prices).
    /// Brunch runs through the lunch period, so it's priced as lunch.
    static let doorPrices: [String: Double] = [
        "Breakfast": 9.50, "Brunch": 16.25, "Lunch": 16.25, "Dinner": 20.25,
    ]
    /// How much cheaper than the door the buyer pays
    static let buyerDiscount: Double = 0.30
    /// Share of the buyer's price the platform keeps
    static let platformCut: Double = 0.15

    static func door(_ meal: String) -> Double { doorPrices[meal] ?? doorPrices["Lunch"]! }

    /// Rounded to whole dollars so prices read cleanly ($7 / $11 / $14)
    static func buyerPrice(_ meal: String) -> Double { (door(meal) * (1 - buyerDiscount)).rounded() }

    static func holderEarns(_ meal: String) -> Double {
        (buyerPrice(meal) * (1 - platformCut) * 100).rounded() / 100
    }

    /// The meal being served at a hall at a given time
    static func meal(at hall: GuestPassHall, _ date: Date) -> String {
        DiningHallSchedule.all[hall.id]?.currentStatus(at: date).currentMeal
            ?? (Calendar.current.component(.hour, from: date) < 11 ? "Breakfast"
                : Calendar.current.component(.hour, from: date) < 16 ? "Lunch" : "Dinner")
    }

    static func format(_ value: Double) -> String {
        value.rounded() == value ? String(format: "$%.0f", value) : String(format: "$%.2f", value)
    }
}

// MARK: - Special hours

/// Dated changes from the UMD Dining calendar (dining.umd.edu/dining-plans/calendar),
/// layered over the regular weekly schedule. Update each semester.
enum DiningSpecialHours {
    struct Period {
        let start: Date
        let end: Date
        let note: String
        /// true = halls closed; false = open on different hours
        let closed: Bool

        func contains(_ date: Date) -> Bool { date >= start && date < end }
    }

    private static func at(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    static let periods: [Period] = [
        Period(start: at(10, 10), end: at(10, 14), note: "Fall break: dining halls are on special hours", closed: false),
        Period(start: at(11, 25, 15), end: at(11, 29, 16), note: "Closed for Thanksgiving break, reopening Nov 29 at 4 PM", closed: true),
        Period(start: at(12, 21, 15), end: at(12, 31, 23, 59), note: "Dining halls closed for winter break", closed: true),
    ]

    static func period(at date: Date = .now) -> Period? { periods.first { $0.contains(date) } }

    /// When fall resident plans (and their guest passes) expire
    static let fallPlansExpire = at(12, 21, 15)
}

// MARK: - Halls

struct GuestPassHall: Identifiable, Hashable {
    let id: String          // matches DiningHallSchedule / hall_<id> image
    let name: String
    /// Fits in a chip
    let shortName: String
    /// Where the two people meet: the card swipe at the entrance
    let meetSpot: String

    var status: DiningHallSchedule.Status {
        if DiningSpecialHours.period()?.closed == true { return .closed }
        return DiningHallSchedule.all[id]?.currentStatus() ?? .closed
    }

    func isOpen(at date: Date) -> Bool {
        if DiningSpecialHours.period(at: date)?.closed == true { return false }
        return DiningHallSchedule.all[id]?.currentStatus(at: date).isOpen ?? false
    }

    // PLACEHOLDER meet spots; check each entrance
    static let all: [GuestPassHall] = [
        GuestPassHall(id: "19", name: "Yahentamitsi", shortName: "Yahentamitsi", meetSpot: "Main entrance, at the card swipe stand"),
        GuestPassHall(id: "51", name: "251 North", shortName: "251 North", meetSpot: "Inside the front doors, by the card swipe"),
        GuestPassHall(id: "16", name: "South Campus Diner", shortName: "South Campus", meetSpot: "Front entrance, at the card swipe"),
    ]

    static func find(_ id: String) -> GuestPassHall { all.first { $0.id == id } ?? all[0] }
}

// MARK: - Timing

enum GuestPassTiming: Hashable {
    case now
    case at(Date)

    var label: String {
        switch self {
        case .now: "Now"
        case .at(let date): date.formatted(date: .omitted, time: .shortened)
        }
    }

    var date: Date {
        switch self {
        case .now: .now
        case .at(let date): date
        }
    }

    /// Half-hour slots over the next few hours while the hall is open
    static func slots(for hall: GuestPassHall, from now: Date = .now, hours: Int = 4) -> [Date] {
        let cal = Calendar.current
        // Truncate to the minute (date(bySetting:) would jump forward to the next minute instead)
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let minute = comps.minute ?? 0
        comps.minute = minute < 30 ? 30 : 0
        guard let base = cal.date(from: comps),
              var slot = minute < 30 ? base : cal.date(byAdding: .hour, value: 1, to: base) else { return [] }
        var result: [Date] = []
        for _ in 0..<(hours * 2) {
            if hall.isOpen(at: slot) { result.append(slot) }
            slot = slot.addingTimeInterval(30 * 60)
        }
        return result
    }
}

// MARK: - Matches

enum GuestPassStatus: Int, Comparable {
    case searching, matched, atDoor, completed
    case expired, cancelled, noShow, disputed

    static func < (lhs: GuestPassStatus, rhs: GuestPassStatus) -> Bool { lhs.rawValue < rhs.rawValue }

    static let track: [GuestPassStatus] = [.matched, .atDoor, .completed]

    var isTerminal: Bool { [.completed, .expired, .cancelled, .noShow, .disputed].contains(self) }

    var title: String {
        switch self {
        case .searching: "Finding"
        case .matched: "Matched"
        case .atDoor: "At the door"
        case .completed: "You're in"
        case .expired: "No match"
        case .cancelled: "Cancelled"
        case .noShow: "No-show"
        case .disputed: "On hold"
        }
    }

    var icon: String {
        switch self {
        case .searching: "magnifyingglass"
        case .matched: "person.2.fill"
        case .atDoor: "door.left.hand.open"
        case .completed: "fork.knife"
        case .expired: "clock.badge.xmark"
        case .cancelled: "xmark.circle.fill"
        case .noShow: "person.fill.questionmark"
        case .disputed: "exclamationmark.shield.fill"
        }
    }
}

enum GuestPassSender { case me, them }

struct GuestPassMessage: Identifiable, Hashable {
    let id = UUID()
    let sender: GuestPassSender
    let text: String
}

enum GuestPassReplies {
    static let buyer = ["On my way 🏃", "Running ~5 min late", "I'm at the swipe stand", "Can't find you, where are you?", "Thanks! 🙏"]
    static let holder = ["On my way 🏃", "Running ~5 min late", "I'm at the swipe stand", "Can't find you, where are you?", "Enjoy!"]
}

/// The buyer's side of a guest pass
struct GuestPassMatch: Identifiable {
    let id = UUID()
    let hall: GuestPassHall
    let timing: GuestPassTiming
    let meal: String
    let requestedAt: Date
    var status: GuestPassStatus
    /// First name + last initial, shown once matched
    var holderName: String?
    var holderRating: Double = 4.9
    var meHere = false
    var themHere = false
    var myNote: String?
    var theirNote: String?
    var messages: [GuestPassMessage] = []
    var myRating: Int?

    var price: Double { GuestPassPricing.buyerPrice(meal) }
    var savings: Double { GuestPassPricing.door(meal) - price }
}

/// A buyer's request as a holder sees it
struct GuestPassRequest: Identifiable {
    let id = UUID()
    let hall: GuestPassHall
    let timing: GuestPassTiming
    let buyerName: String
    var buyerRating: Double = 5.0
    let postedMinutesAgo: Int

    var meal: String { GuestPassPricing.meal(at: hall, timing.date) }
    var holderEarns: Double { GuestPassPricing.holderEarns(meal) }
}

enum GuestPassJobStep: Int {
    case heading, atDoor, waitingConfirm, rate, done
}

/// A holder's accepted request
struct GuestPassJob: Identifiable {
    let request: GuestPassRequest
    var step: GuestPassJobStep = .heading
    var meHere = false
    var themHere = false
    var myNote: String?
    var theirNote: String?
    var messages: [GuestPassMessage] = []
    var id: UUID { request.id }
}

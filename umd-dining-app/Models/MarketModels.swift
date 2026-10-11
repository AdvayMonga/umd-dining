import Foundation

// MARK: - Pricing

enum MarketPricing {
    /// Buyers never pay more than this fraction of the Dining Dollar price
    static let maxRate: Double = 0.80
    /// Rates a seller can pick; anything at or below the cap
    static let sellerRates: [Double] = [0.80, 0.75, 0.70]
    /// Share of what the buyer pays that goes to the platform
    static let platformCut: Double = 0.10

    static func sellerTake(buyerPays: Double) -> Double {
        buyerPays * (1 - platformCut)
    }
}

// MARK: - Locations

struct MarketLocation: Identifiable, Hashable {
    let id: String
    let name: String
    let building: String
    let isLive: Bool
    /// Stop taking requests this long before close so sellers can still order
    var lastCallMinutes: Int = 15

    static func == (lhs: MarketLocation, rhs: MarketLocation) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var schedule: DiningHallSchedule? { MarketMenu.schedules[id] }

    /// Chick-fil-A is closed on Sundays, which DiningHallSchedule can't express
    var closedOnSundays: Bool { id.hasPrefix("cfa") }

    func status(at date: Date = .now) -> DiningHallSchedule.Status {
        if closedOnSundays && Calendar.current.component(.weekday, from: date) == 1 { return .closed }
        return schedule?.currentStatus(at: date) ?? .closed
    }

    /// Open and not inside last call
    func isTakingOrders(at date: Date = .now) -> Bool {
        let s = status(at: date)
        guard s.isOpen else { return false }
        let soon = date.addingTimeInterval(TimeInterval(lastCallMinutes * 60))
        return status(at: soon).isOpen
    }
}

// MARK: - Items & options

struct OptionChoice: Identifiable, Hashable {
    let id: String
    let name: String
    var priceDelta: Double = 0
}

/// A Grubhub-style option group: "Choose a side", "Add sauces (up to 2)"
struct OptionGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let choices: [OptionChoice]
    var minSelect: Int = 0
    var maxSelect: Int = 1

    var isRequired: Bool { minSelect > 0 }
    var isSingle: Bool { maxSelect == 1 }

    var rule: String {
        if isRequired && isSingle { return "Required" }
        if isRequired { return "Choose \(minSelect)–\(maxSelect)" }
        return isSingle ? "Optional" : "Up to \(maxSelect)"
    }
}

struct MarketItem: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let emoji: String
    /// Menu price in Dining Dollars (no sales tax on DD)
    let ddPrice: Double
    /// Grubhub captures usually don't include calories
    var calories: Int?
    var detail: String = ""
    var options: [OptionGroup] = []
}

/// One configured item in the cart: item + chosen options + quantity
struct CartLine: Identifiable, Hashable {
    let item: MarketItem
    /// groupId → chosen choice ids, in pick order
    let selections: [String: [String]]
    var quantity: Int

    var id: String {
        item.id + "|" + selections.keys.sorted().map { "\($0)=\(selections[$0]!.joined(separator: ","))" }.joined(separator: ";")
    }

    var chosen: [OptionChoice] {
        item.options.flatMap { group in
            (selections[group.id] ?? []).compactMap { cid in group.choices.first { $0.id == cid } }
        }
    }

    var unitPrice: Double { item.ddPrice + chosen.reduce(0) { $0 + $1.priceDelta } }
    var ddTotal: Double { unitPrice * Double(quantity) }
    /// "Waffle Fries · Lemonade · Polynesian"
    var summary: String { chosen.map(\.name).joined(separator: " · ") }
}

// MARK: - Orders

enum OrderStatus: Int, Comparable {
    case searching, matched, placed, ready, pickedUp
    case expired, cancelled, disputed

    static func < (lhs: OrderStatus, rhs: OrderStatus) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Steps drawn on the progress track
    static let track: [OrderStatus] = [.matched, .placed, .ready, .pickedUp]

    var isTerminal: Bool { [.pickedUp, .expired, .cancelled, .disputed].contains(self) }
    var canCancel: Bool { self == .searching || self == .matched }
    var canReportProblem: Bool { self == .placed || self == .ready }

    var title: String {
        switch self {
        case .searching: "Finding"
        case .matched: "Matched"
        case .placed: "Ordered"
        case .ready: "Ready"
        case .pickedUp: "Picked up"
        case .expired: "No match"
        case .cancelled: "Cancelled"
        case .disputed: "On hold"
        }
    }

    var icon: String {
        switch self {
        case .searching: "magnifyingglass"
        case .matched: "person.2.fill"
        case .placed: "bag.fill"
        case .ready: "checkmark.seal.fill"
        case .pickedUp: "hand.thumbsup.fill"
        case .expired: "clock.badge.xmark"
        case .cancelled: "xmark.circle.fill"
        case .disputed: "exclamationmark.shield.fill"
        }
    }

    var buyerMessage: String {
        switch self {
        case .searching: "Looking for a seller near Stamp. You won't be charged unless someone accepts."
        case .matched: "A seller accepted. They're placing your order on Grubhub now."
        case .placed: "Order placed. Chick-fil-A is making it."
        case .ready: "Ready at the Stamp pickup shelf. Say your pickup code or order #."
        case .pickedUp: "Enjoy! Payment released to your seller."
        case .expired: "No sellers picked this up in time. You weren't charged."
        case .cancelled: "Cancelled. You weren't charged."
        case .disputed: "Payment is on hold while we sort this out. We'll update you within 24 hours."
        }
    }
}

enum ProblemReason: String, CaseIterable, Identifiable {
    case notThere = "Order isn't at the pickup shelf"
    case missingItem = "Something's missing"
    case wrongItem = "Wrong item"
    case noOrderNumber = "Seller never placed the order"
    case other = "Something else"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .notThere: "questionmark.square.dashed"
        case .missingItem: "minus.circle"
        case .wrongItem: "arrow.triangle.swap"
        case .noOrderNumber: "clock.badge.exclamationmark"
        case .other: "ellipsis.bubble"
        }
    }
}

// MARK: - Quick replies

enum MessageSender { case me, them }

struct QuickMessage: Identifiable, Hashable {
    let id = UUID()
    let sender: MessageSender
    let text: String
}

enum QuickReplies {
    static let buyer = [
        "On my way 🏃",
        "Running ~10 min late",
        "Can't find it on the shelf",
        "Swap is fine 👍",
        "Thanks! 🙏",
    ]
    static let seller = [
        "Order's in, should be quick",
        "They're out of an item. OK to swap for something similar?",
        "Running a few min behind",
        "It's ready, say your code at the shelf",
    ]
}

// MARK: - Buyer order

struct MarketOrder: Identifiable {
    let id = UUID()
    let lines: [CartLine]
    let location: MarketLocation
    let rate: Double
    /// Anonymous name the seller puts on the Grubhub order; neither side sees a real name
    let pickupCode: String
    let placedAt: Date
    var orderNumber: String?
    var status: OrderStatus
    var sellerRating: Double = 4.9
    var messages: [QuickMessage] = []
    var problem: ProblemReason?
    var myRating: Int?

    var ddTotal: Double { lines.reduce(0) { $0 + $1.ddTotal } }
    var buyerPays: Double { ddTotal * rate }
    var savings: Double { ddTotal - buyerPays }
}

// MARK: - Seller side

/// A buyer's request as a seller sees it
struct MarketRequest: Identifiable {
    let id = UUID()
    let pickupCode: String
    let lines: [CartLine]
    let location: MarketLocation
    let postedMinutesAgo: Int
    var buyerRating: Double = 5.0

    var ddTotal: Double { lines.reduce(0) { $0 + $1.ddTotal } }

    /// What the seller nets when filling this at their rate
    func sellerEarns(at rate: Double) -> Double {
        MarketPricing.sellerTake(buyerPays: ddTotal * rate)
    }
}

enum SellerJobStep: Int {
    case placeOrder, markReady, waitingPickup, rate, done
}

struct SellerJob: Identifiable {
    let request: MarketRequest
    let rate: Double
    var step: SellerJobStep
    var orderNumber: String = ""
    var hasScreenshot = false
    var messages: [QuickMessage] = []
    var id: UUID { request.id }
}

// MARK: - Dining Dollar pace

struct DiningDollarPace {
    let balance: Double
    /// Average spend per week so far this semester
    let weeklySpend: Double
    let weeksLeft: Double
    let expiresOn: Date

    var projectedSpend: Double { weeklySpend * weeksLeft }
    var projectedSurplus: Double { max(0, balance - projectedSpend) }
    /// 0...1, how much of the balance you're on pace to use
    var usageFraction: Double { balance > 0 ? min(1, projectedSpend / balance) : 1 }
}

// MARK: - Helpers

enum PickupCode {
    /// Short, easy to say at the counter: "Terp 48"
    static func make() -> String { "Terp \(Int.random(in: 10...99))" }
}

extension Double {
    /// "$5.17"
    var dollars: String { String(format: "$%.2f", self) }
    /// "$312" when whole, else "$5.17"
    var dollarsShort: String {
        rounded() == self ? String(format: "$%.0f", self) : dollars
    }
}

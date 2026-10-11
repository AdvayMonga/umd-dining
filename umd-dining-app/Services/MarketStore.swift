import SwiftUI

/// Marketplace state. Sample data only for now; the API will replace the sample
/// collections and the demo timers once the backend exists.
@MainActor
@Observable
class MarketStore {
    static let shared = MarketStore()

    /// How long a request waits for a seller before it expires
    static let matchTimeout: TimeInterval = 5 * 60

    // MARK: Buy side

    let locations: [MarketLocation] = MarketMenu.locations
    var selectedLocationId = "cfa-stamp"
    var cart: [CartLine] = []
    var activeOrder: MarketOrder?
    /// DEBUG: lets you try ordering outside real hours
    var ignoreHours = false

    /// Rates of sellers currently online at the selected location
    var onlineSellerRates: [Double] = [0.80, 0.75, 0.80, 0.78]

    var selectedLocation: MarketLocation {
        locations.first { $0.id == selectedLocationId } ?? locations[0]
    }

    var items: [MarketItem] {
        MarketMenu.items[selectedLocationId] ?? []
    }

    var isTakingOrders: Bool { ignoreHours || selectedLocation.isTakingOrders() }

    /// Best price a buyer can get right now, never above the cap
    var bestRate: Double {
        min(onlineSellerRates.min() ?? MarketPricing.maxRate, MarketPricing.maxRate)
    }

    var discountPercent: Int { Int(((1 - bestRate) * 100).rounded()) }

    var cartCount: Int { cart.reduce(0) { $0 + $1.quantity } }
    var cartDDTotal: Double { cart.reduce(0) { $0 + $1.ddTotal } }
    var cartPrice: Double { cartDDTotal * bestRate }

    func quantity(of item: MarketItem) -> Int {
        cart.filter { $0.item.id == item.id }.reduce(0) { $0 + $1.quantity }
    }

    func add(_ item: MarketItem, selections: [String: [String]] = [:], quantity: Int = 1) {
        let line = CartLine(item: item, selections: selections, quantity: quantity)
        if let i = cart.firstIndex(where: { $0.id == line.id }) {
            cart[i].quantity += quantity
        } else {
            cart.append(line)
        }
    }

    func increment(_ line: CartLine) {
        guard let i = cart.firstIndex(where: { $0.id == line.id }) else { return }
        cart[i].quantity += 1
    }

    func decrement(_ line: CartLine) {
        guard let i = cart.firstIndex(where: { $0.id == line.id }) else { return }
        cart[i].quantity -= 1
        if cart[i].quantity <= 0 { cart.remove(at: i) }
    }

    /// Card "−" button: take one off the most recently added line of this item
    func removeOne(of item: MarketItem) {
        guard let line = cart.last(where: { $0.item.id == item.id }) else { return }
        decrement(line)
    }

    func placeOrder() {
        activeOrder = MarketOrder(
            lines: cart,
            location: selectedLocation,
            rate: bestRate,
            pickupCode: PickupCode.make(),
            placedAt: .now,
            orderNumber: nil,
            status: .searching
        )
        cart = []
        runDemoProgression()
    }

    func cancelOrder() {
        guard let order = activeOrder, order.status.canCancel else { return }
        activeOrder?.status = .cancelled
    }

    func reportProblem(_ reason: ProblemReason) {
        activeOrder?.problem = reason
        activeOrder?.status = .disputed
    }

    func confirmPickup() {
        activeOrder?.status = .pickedUp
    }

    func rateSeller(_ stars: Int) {
        activeOrder?.myRating = stars
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.spring(duration: 0.4)) { activeOrder = nil }
        }
    }

    func dismissOrder() {
        activeOrder = nil
    }

    /// Expired or cancelled: put the items back in the cart to try again
    func retryOrder() {
        guard let order = activeOrder else { return }
        cart = order.lines
        activeOrder = nil
    }

    func expireIfStale(now: Date = .now) {
        guard let order = activeOrder, order.status == .searching,
              now.timeIntervalSince(order.placedAt) >= Self.matchTimeout else { return }
        activeOrder?.status = .expired
    }

    func sendBuyerMessage(_ text: String) {
        activeOrder?.messages.append(QuickMessage(sender: .me, text: text))
    }

    /// Steps the order forward so the tracking UI can be seen without a backend.
    /// Each step checks the status it expects so a cancel or report stops it.
    private func runDemoProgression() {
        let id = activeOrder?.id
        func advance(from expected: OrderStatus, _ change: (inout MarketOrder) -> Void) {
            guard activeOrder?.id == id, activeOrder?.status == expected else { return }
            withAnimation(.spring(duration: 0.4)) { change(&activeOrder!) }
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            advance(from: .searching) { $0.status = .matched }
            try? await Task.sleep(for: .seconds(4))
            advance(from: .matched) {
                $0.status = .placed
                $0.orderNumber = "4821"
                $0.messages.append(QuickMessage(sender: .them, text: QuickReplies.seller[0]))
            }
            try? await Task.sleep(for: .seconds(5))
            advance(from: .placed) { $0.status = .ready }
        }
    }

    // MARK: Sell side

    var isSelling = true
    var sellerRate: Double = 0.75
    var sellerRating: Double = 4.9
    var completedJobs = 12
    var pace = MarketSampleData.pace
    var requests: [MarketRequest] = MarketSampleData.requests
    var jobs: [SellerJob] = []
    var earnedThisSemester: Double = 46.20

    func accept(_ request: MarketRequest) {
        requests.removeAll { $0.id == request.id }
        jobs.insert(SellerJob(request: request, rate: sellerRate, step: .placeOrder), at: 0)
    }

    func updateJob(_ job: SellerJob, _ change: (inout SellerJob) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        change(&jobs[i])
    }

    func submitProof(_ job: SellerJob, orderNumber: String, reading: OrderScreenshotReader.Reading?) {
        updateJob(job) {
            $0.orderNumber = orderNumber
            $0.hasScreenshot = reading != nil
            $0.step = .markReady
        }
        // Grubhub charged a different amount than our menu says: the menu needs a refresh
        if let grubhub = reading?.subtotalMismatch(expected: job.request.ddTotal) {
            flagMenu(job.request, grubhub: grubhub)
        }
    }

    func flagMenu(_ request: MarketRequest, grubhub: Double) {
        // One flag per order, whether it came from the bag check or the screenshot
        guard !menuFlags.contains(where: { $0.requestId == request.id }) else { return }
        menuFlags.append(MenuPriceFlag(
            requestId: request.id,
            locationId: request.location.id,
            menuVersion: MarketMenu.capturedOn[request.location.id] ?? "placeholder",
            expected: request.ddTotal,
            grubhub: grubhub,
            items: request.lines.map(\.item.name)
        ))
    }

    /// Seller backs out before paying (e.g. the bag total didn't match); the request goes back to the pool
    func releaseJob(_ job: SellerJob, grubhubBag: Double?) {
        if let grubhubBag { flagMenu(job.request, grubhub: grubhubBag) }
        jobs.removeAll { $0.id == job.id }
        requests.insert(job.request, at: 0)
    }

    /// Price mismatches from real orders; will be sent to the backend once it exists
    var menuFlags: [MenuPriceFlag] = []

    func markReady(_ job: SellerJob) {
        updateJob(job) { $0.step = .waitingPickup }
        // Demo: the buyer confirms pickup a few seconds later
        let id = job.id
        Task {
            try? await Task.sleep(for: .seconds(3))
            guard let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].step == .waitingPickup else { return }
            withAnimation(.spring(duration: 0.4)) {
                jobs[i].step = .rate
                earnedThisSemester += jobs[i].request.sellerEarns(at: jobs[i].rate)
                completedJobs += 1
                pace = DiningDollarPace(
                    balance: pace.balance - jobs[i].request.ddTotal,
                    weeklySpend: pace.weeklySpend,
                    weeksLeft: pace.weeksLeft,
                    expiresOn: pace.expiresOn
                )
            }
        }
    }

    func rateBuyer(_ job: SellerJob, thumbsUp: Bool) {
        updateJob(job) { $0.step = .done }
        let id = job.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.spring(duration: 0.4)) { jobs.removeAll { $0.id == id } }
        }
    }

    func sendSellerMessage(_ job: SellerJob, _ text: String) {
        updateJob(job) { $0.messages.append(QuickMessage(sender: .me, text: text)) }
    }
}

// MARK: - Sample data

enum MarketSampleData {
    static let pace = DiningDollarPace(
        balance: 312,
        weeklySpend: 9.5,
        weeksLeft: 21,
        expiresOn: Calendar.current.date(from: DateComponents(year: 2027, month: 5, day: 19)) ?? .now
    )

    static var requests: [MarketRequest] {
        let cfa = MarketMenu.locations[0]
        func line(_ id: String, _ selections: [String: [String]], _ qty: Int = 1) -> CartLine {
            CartLine(item: MarketMenu.placeholderItem(id)!, selections: selections, quantity: qty)
        }
        return [
            MarketRequest(pickupCode: "Terp 31", lines: [
                line("cfa-spicy-meal", ["size": ["m"], "side": ["fries"], "drink": ["lemonade"], "sauce": ["cfa"]]),
                line("cfa-shake", ["flavor": ["cookies"]]),
            ], location: cfa, postedMinutesAgo: 1, buyerRating: 4.8),
            MarketRequest(pickupCode: "Terp 57", lines: [
                line("cfa-nuggets-12", ["sauce": ["poly", "bbq"]]),
                line("cfa-fries", ["size": ["m"]], 2),
            ], location: cfa, postedMinutesAgo: 3),
            MarketRequest(pickupCode: "Terp 82", lines: [
                line("cfa-cobb", ["dressing": ["avocado-lime"]]),
            ], location: cfa, postedMinutesAgo: 6, buyerRating: 4.6),
        ]
    }
}

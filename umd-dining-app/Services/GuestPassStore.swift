import SwiftUI

/// Guest pass marketplace state. Sample data and demo timers stand in for the
/// other person until the backend exists.
@MainActor
@Observable
class GuestPassStore {
    static let shared = GuestPassStore()

    // MARK: Buyer

    var selectedHallId = "19"
    var timing: GuestPassTiming = .now
    var activeMatch: GuestPassMatch?

    /// Holders free right now / later today, per hall
    var freeNow: [String: Int] = ["19": 3, "51": 2, "16": 1]
    var scheduledHolders: [String: Int] = ["19": 7, "51": 4, "16": 3]

    var selectedHall: GuestPassHall { GuestPassHall.find(selectedHallId) }

    /// Meal for the current hall and time choice; sets the price
    var selectedMeal: String { GuestPassPricing.meal(at: selectedHall, timing.date) }

    func holdersFreeNow(at hall: GuestPassHall) -> Int { hall.status.isOpen ? freeNow[hall.id] ?? 0 : 0 }

    func request() {
        activeMatch = GuestPassMatch(
            hall: selectedHall,
            timing: timing,
            meal: selectedMeal,
            requestedAt: .now,
            status: .searching
        )
        runBuyerDemo()
    }

    func cancel() {
        guard let status = activeMatch?.status, status == .searching || status == .matched else { return }
        activeMatch?.status = .cancelled
    }

    func setBuyerHere(note: String?) {
        activeMatch?.meHere = true
        activeMatch?.myNote = note
        if activeMatch?.themHere == true { activeMatch?.status = .atDoor }
    }

    func confirmIn() { activeMatch?.status = .completed }

    func reportNoShow() { activeMatch?.status = .noShow }

    func reportProblem() { activeMatch?.status = .disputed }

    func rateHolder(_ stars: Int) {
        activeMatch?.myRating = stars
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.spring(duration: 0.4)) { activeMatch = nil }
        }
    }

    func dismissMatch() { activeMatch = nil }

    func sendBuyerMessage(_ text: String) {
        activeMatch?.messages.append(GuestPassMessage(sender: .me, text: text))
    }

    func expireIfStale(now: Date = .now) {
        guard let match = activeMatch, match.status == .searching, match.timing == .now,
              now.timeIntervalSince(match.requestedAt) >= GuestPassRules.matchTimeout else { return }
        activeMatch?.status = .expired
    }

    /// Demo: a holder accepts, heads over and arrives. Each step checks the
    /// status it expects so cancelling stops it.
    private func runBuyerDemo() {
        let id = activeMatch?.id
        func step(from expected: GuestPassStatus, _ change: (inout GuestPassMatch) -> Void) {
            guard activeMatch?.id == id, activeMatch?.status == expected else { return }
            withAnimation(.spring(duration: 0.4)) { change(&activeMatch!) }
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            step(from: .searching) {
                $0.status = .matched
                $0.holderName = "Jordan K."
                $0.messages.append(GuestPassMessage(sender: .them, text: "On my way 🏃"))
            }
            try? await Task.sleep(for: .seconds(5))
            step(from: .matched) {
                $0.themHere = true
                $0.theirNote = "Black jacket"
                if $0.meHere { $0.status = .atDoor }
            }
        }
    }

    // MARK: Holder

    var planName: String? = "Premium"
    var passesLeft = 6
    let passesExpire = DiningSpecialHours.fallPlansExpire
    var isAvailable = true
    var availableHallIds: Set<String> = ["19", "51"]
    var holderRating: Double = 4.9
    var passesSold = 3
    var earnedThisSemester: Double = 27.00
    var requests: [GuestPassRequest] = GuestPassSampleData.requests
    var jobs: [GuestPassJob] = []

    var visibleRequests: [GuestPassRequest] {
        requests.filter { availableHallIds.contains($0.hall.id) }
    }

    /// What your remaining passes earn if each is sold for dinner
    var passesValue: Double { Double(passesLeft) * GuestPassPricing.holderEarns("Dinner") }

    func setPlan(_ plan: String, passes: Int) {
        planName = plan
        passesLeft = passes
    }

    func accept(_ request: GuestPassRequest) {
        guard passesLeft > 0 else { return }
        requests.removeAll { $0.id == request.id }
        jobs.insert(GuestPassJob(request: request), at: 0)
    }

    private func updateJob(_ job: GuestPassJob, _ change: (inout GuestPassJob) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        change(&jobs[i])
    }

    func setHolderHere(_ job: GuestPassJob, note: String?) {
        updateJob(job) {
            $0.meHere = true
            $0.myNote = note
        }
        // Demo: the buyer arrives a few seconds later
        let id = job.id
        Task {
            try? await Task.sleep(for: .seconds(3))
            guard let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].step == .heading else { return }
            withAnimation(.spring(duration: 0.4)) {
                jobs[i].themHere = true
                jobs[i].theirNote = "Red hoodie"
                jobs[i].step = .atDoor
            }
        }
    }

    func swipedIn(_ job: GuestPassJob) {
        updateJob(job) { $0.step = .waitingConfirm }
        // Demo: the buyer confirms they got in
        let id = job.id
        Task {
            try? await Task.sleep(for: .seconds(2))
            guard let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].step == .waitingConfirm else { return }
            withAnimation(.spring(duration: 0.4)) {
                jobs[i].step = .rate
                passesLeft = max(0, passesLeft - 1)
                passesSold += 1
                earnedThisSemester += jobs[i].request.holderEarns
            }
        }
    }

    func holderReportNoShow(_ job: GuestPassJob) {
        jobs.removeAll { $0.id == job.id }
    }

    func rateBuyer(_ job: GuestPassJob, thumbsUp: Bool) {
        updateJob(job) { $0.step = .done }
        let id = job.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.spring(duration: 0.4)) { jobs.removeAll { $0.id == id } }
        }
    }

    func sendHolderMessage(_ job: GuestPassJob, _ text: String) {
        updateJob(job) { $0.messages.append(GuestPassMessage(sender: .me, text: text)) }
    }
}

enum GuestPassSampleData {
    static var requests: [GuestPassRequest] {
        let cal = Calendar.current
        let dinner = cal.date(bySettingHour: 18, minute: 0, second: 0, of: .now) ?? .now
        return [
            GuestPassRequest(hall: GuestPassHall.find("19"), timing: .now, buyerName: "Maya R.", buyerRating: 4.8, postedMinutesAgo: 1),
            GuestPassRequest(hall: GuestPassHall.find("51"), timing: .at(dinner), buyerName: "Chris T.", postedMinutesAgo: 4),
            GuestPassRequest(hall: GuestPassHall.find("16"), timing: .now, buyerName: "Priya S.", buyerRating: 4.6, postedMinutesAgo: 6),
            GuestPassRequest(hall: GuestPassHall.find("19"), timing: .at(dinner.addingTimeInterval(1800)), buyerName: "Sam L.", postedMinutesAgo: 9),
        ]
    }
}

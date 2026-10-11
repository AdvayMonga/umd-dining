import Foundation

/// /api/hours: UMD Dining's published schedule, per hall and date.
/// A date with [] is closed all day; a missing date means the schedule doesn't say.
struct HallHoursResponse: Codable, Sendable {
    struct Window: Codable, Sendable {
        let meal: String
        let open: String   // "HH:mm", campus time; close may be "24:00"
        let close: String
    }

    let halls: [String: [String: [Window]]]
    let fetchedAt: String?

    enum CodingKeys: String, CodingKey {
        case halls
        case fetchedAt = "fetched_at"
    }

    /// hallId -> "yyyy-MM-dd" -> windows sorted by open time. Unparseable windows are
    /// dropped; a date whose windows were all unparseable is dropped too (unknown, not closed).
    var mealWindows: [String: [String: [MealWindow]]] {
        halls.mapValues { days in
            days.compactMapValues { raw in
                let windows = raw.compactMap { w -> MealWindow? in
                    guard let open = Self.minutes(w.open), let close = Self.minutes(w.close), open < close else { return nil }
                    return MealWindow(name: w.meal, openMinute: open, closeMinute: close)
                }
                if windows.isEmpty && !raw.isEmpty { return nil }
                return windows.sorted { $0.openMinute < $1.openMinute }
            }
        }
    }

    static func minutes(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h) || (h == 24 && m == 0), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }
}

/// Live hall hours with an offline copy; falls back to the hardcoded
/// DiningHallSchedule for any day the live data doesn't cover.
@MainActor
@Observable
class HallHoursService {
    static let shared = HallHoursService()

    private(set) var days: [String: [String: [MealWindow]]] = [:]
    private var lastAttempt: Date?
    private var lastAttemptSucceeded = false
    private var isRefreshing = false

    private static let cacheKey = "hallHoursCache"
    private static let refreshInterval: TimeInterval = 3600
    private static let retryInterval: TimeInterval = 300

    private let defaults: UserDefaults
    private let fetch: () async throws -> HallHoursResponse
    private let now: () -> Date

    init(defaults: UserDefaults = .standard,
         fetch: @escaping () async throws -> HallHoursResponse = { try await DiningAPIService.shared.fetchHallHours() },
         now: @escaping () -> Date = { .now }) {
        self.defaults = defaults
        self.fetch = fetch
        self.now = now
        if let data = defaults.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(HallHoursResponse.self, from: data) {
            days = cached.mealWindows
        }
    }

    func status(for hallId: String, at date: Date = .now) -> DiningHallSchedule.Status {
        if let hallDays = days[hallId],
           let live = DiningHallSchedule.status(days: hallDays, at: date) {
            return live
        }
        return DiningHallSchedule.all[hallId]?.currentStatus(at: date) ?? .closed
    }

    /// Hourly after a success, every 5 min after a failure; failures keep whatever is cached
    func refreshIfNeeded() async {
        guard !isRefreshing else { return }
        if let lastAttempt,
           now().timeIntervalSince(lastAttempt) < (lastAttemptSucceeded ? Self.refreshInterval : Self.retryInterval) {
            return
        }
        // Recorded before awaiting, so overlapping calls and failures are throttled too
        isRefreshing = true
        lastAttempt = now()
        lastAttemptSucceeded = false
        defer { isRefreshing = false }
        guard let response = try? await fetch() else { return }
        apply(response)
    }

    func apply(_ response: HallHoursResponse) {
        lastAttempt = now()
        lastAttemptSucceeded = true
        days = response.mealWindows
        if let data = try? JSONEncoder().encode(response) {
            defaults.set(data, forKey: Self.cacheKey)
        }
    }
}

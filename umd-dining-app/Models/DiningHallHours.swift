import Foundation

struct MealWindow {
    let name: String
    let openMinute: Int   // minutes from midnight
    let closeMinute: Int

    func contains(minute: Int) -> Bool {
        minute >= openMinute && minute < closeMinute
    }

    var openTimeString: String { minuteToString(openMinute) }
    var closeTimeString: String { minuteToString(closeMinute) }

    private func minuteToString(_ m: Int) -> String {
        let hour = m / 60
        let min = m % 60
        let period = hour < 12 ? "AM" : "PM"
        let displayHour = hour == 0 ? 12 : hour > 12 ? hour - 12 : hour
        return min == 0 ? "\(displayHour) \(period)" : "\(displayHour):\(String(format: "%02d", min)) \(period)"
    }
}

struct DiningHallSchedule {
    let hallId: String
    let weekdayWindows: [MealWindow]             // Mon–Thu
    let fridayWindows: [MealWindow]?             // Fri only; nil = same as weekday
    let weekendWindows: [MealWindow]             // Sat–Sun

    init(hallId: String, weekdayWindows: [MealWindow], fridayWindows: [MealWindow]? = nil, weekendWindows: [MealWindow]) {
        self.hallId = hallId
        self.weekdayWindows = weekdayWindows
        self.fridayWindows = fridayWindows
        self.weekendWindows = weekendWindows
    }

    struct Status {
        let isOpen: Bool
        let isClosingSoon: Bool   // last meal of the day, closes within 30 min
        let currentMeal: String?
        let closeTime: String?    // current meal's close (unused in UI but kept for flexibility)
        let dayCloseTime: String? // last meal's close = when the hall closes for the day
        let nextMeal: String?
        let nextOpenTime: String?
        var nextOpenDay: String? = nil  // "tomorrow" / "Tue" when the next opening isn't today

        static let closed = Status(isOpen: false, isClosingSoon: false, currentMeal: nil, closeTime: nil, dayCloseTime: nil, nextMeal: nil, nextOpenTime: nil)
    }

    func currentStatus(at date: Date = .now) -> Status {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)  // 1=Sun, 6=Fri, 7=Sat
        let isWeekend = weekday == 1 || weekday == 7
        let isFriday = weekday == 6
        let windows = isWeekend ? weekendWindows : (isFriday ? (fridayWindows ?? weekdayWindows) : weekdayWindows)
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        let minute = h * 60 + m

        let dayCloseTime = windows.last?.closeTimeString

        for (i, window) in windows.enumerated() {
            if window.contains(minute: minute) {
                let isLastMeal = i == windows.count - 1
                let isClosingSoon = isLastMeal && (window.closeMinute - minute) <= 30
                return Status(
                    isOpen: true,
                    isClosingSoon: isClosingSoon,
                    currentMeal: window.name,
                    closeTime: window.closeTimeString,
                    dayCloseTime: dayCloseTime,
                    nextMeal: nil,
                    nextOpenTime: nil
                )
            }
        }
        for window in windows where window.openMinute > minute {
            return Status(isOpen: false, isClosingSoon: false, currentMeal: nil, closeTime: nil, dayCloseTime: dayCloseTime, nextMeal: window.name, nextOpenTime: window.openTimeString)
        }
        return .closed
    }

    /// Status from live hours (hall's "yyyy-MM-dd" -> windows; [] = closed all day).
    /// nil when today isn't in the data, so the caller falls back to the hardcoded week.
    static func status(days: [String: [MealWindow]], at date: Date, calendar: Calendar = .current) -> Status? {
        guard let windows = days[dateKey(date, calendar: calendar)] else { return nil }
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)

        if let i = windows.firstIndex(where: { $0.contains(minute: minute) }) {
            // Back-to-back meals (Lunch 10:30–4, Dinner 4–9) are one open stretch;
            // a gap between meals (summer hours) closes the hall until the next one
            var end = i
            while end + 1 < windows.count && windows[end + 1].openMinute <= windows[end].closeMinute {
                end += 1
            }
            let closesAt = windows[end].closeMinute
            return Status(
                isOpen: true,
                isClosingSoon: closesAt - minute <= 30,
                currentMeal: windows[i].name,
                closeTime: windows[i].closeTimeString,
                dayCloseTime: windows[end].closeTimeString,
                nextMeal: nil,
                nextOpenTime: nil
            )
        }
        if let next = windows.first(where: { $0.openMinute > minute }) {
            return Status(isOpen: false, isClosingSoon: false, currentMeal: nil, closeTime: nil,
                          dayCloseTime: windows.last?.closeTimeString, nextMeal: next.name, nextOpenTime: next.openTimeString)
        }
        // Done for today: look ahead to the next open day, stopping where the data runs out
        for offset in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date),
                  let later = days[dateKey(day, calendar: calendar)] else { break }
            if let first = later.first {
                return Status(isOpen: false, isClosingSoon: false, currentMeal: nil, closeTime: nil,
                              dayCloseTime: nil, nextMeal: first.name, nextOpenTime: first.openTimeString,
                              nextOpenDay: offset == 1 ? "tomorrow" : weekdayName(day, calendar: calendar))
            }
        }
        return .closed
    }

    static func dateKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func weekdayName(_ date: Date, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: date)  // 1 = Sun
        return calendar.shortWeekdaySymbols[weekday - 1]
    }

    // Hardcoded hours — week of 4/27–5/3. Fallback only: HallHoursService serves UMD's live
    // schedule when it has data for the day (verify each semester against UMD Dining schedule)
    static let all: [String: DiningHallSchedule] = [
        "19": DiningHallSchedule(
            hallId: "19",
            weekdayWindows: [
                MealWindow(name: "Breakfast", openMinute: 7 * 60,       closeMinute: 10 * 60 + 30),
                MealWindow(name: "Lunch",     openMinute: 10 * 60 + 30, closeMinute: 16 * 60),
                MealWindow(name: "Dinner",    openMinute: 16 * 60,      closeMinute: 21 * 60)
            ],
            weekendWindows: [
                MealWindow(name: "Brunch", openMinute: 10 * 60, closeMinute: 16 * 60),
                MealWindow(name: "Dinner", openMinute: 16 * 60, closeMinute: 21 * 60)
            ]
        ),
        "51": DiningHallSchedule(
            hallId: "51",
            weekdayWindows: [                                            // Mon–Thu
                MealWindow(name: "Breakfast", openMinute: 8 * 60,       closeMinute: 10 * 60 + 30),
                MealWindow(name: "Lunch",     openMinute: 10 * 60 + 30, closeMinute: 16 * 60),
                MealWindow(name: "Dinner",    openMinute: 16 * 60,      closeMinute: 22 * 60)
            ],
            fridayWindows: [                                             // Fri dinner ends at 7
                MealWindow(name: "Breakfast", openMinute: 8 * 60,       closeMinute: 10 * 60 + 30),
                MealWindow(name: "Lunch",     openMinute: 10 * 60 + 30, closeMinute: 16 * 60),
                MealWindow(name: "Dinner",    openMinute: 16 * 60,      closeMinute: 19 * 60)
            ],
            weekendWindows: [
                MealWindow(name: "Breakfast", openMinute: 8 * 60,       closeMinute: 10 * 60 + 30),
                MealWindow(name: "Lunch",     openMinute: 10 * 60 + 30, closeMinute: 16 * 60),
                MealWindow(name: "Dinner",    openMinute: 16 * 60,      closeMinute: 19 * 60)
            ]
        ),
        "16": DiningHallSchedule(
            hallId: "16",
            weekdayWindows: [
                MealWindow(name: "Breakfast", openMinute: 7 * 60,       closeMinute: 10 * 60 + 30),
                MealWindow(name: "Lunch",     openMinute: 10 * 60 + 30, closeMinute: 16 * 60),
                MealWindow(name: "Dinner",    openMinute: 16 * 60,      closeMinute: 21 * 60)
            ],
            weekendWindows: [
                MealWindow(name: "Brunch", openMinute: 10 * 60, closeMinute: 16 * 60),
                MealWindow(name: "Dinner", openMinute: 16 * 60, closeMinute: 21 * 60)
            ]
        )
    ]
}

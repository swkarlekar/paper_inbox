import Foundation

public struct PaperIDGenerator {
    public static func makeID(
        date: Date = Date(),
        existingIDs: [String],
        calendar: Calendar = .current
    ) -> String {
        let day = dayString(for: date, calendar: calendar)
        let prefix = "P-\(day)-"
        let largestSuffix = existingIDs
            .filter { $0.hasPrefix(prefix) }
            .compactMap { Int($0.suffix(4)) }
            .max() ?? 0

        return "\(prefix)\(String(format: "%04d", largestSuffix + 1))"
    }

    public static func dayString(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

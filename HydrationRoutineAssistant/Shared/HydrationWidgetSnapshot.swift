import Foundation

struct HydrationWidgetSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let dayStart: Date
    let dayEnd: Date
    let timeZoneIdentifier: String
    let targetMillilitres: Int?
    let consumedMillilitres: Int
    let lastIntakeAt: Date?
    let updatedAt: Date

    init(
        day: DateInterval, timeZoneIdentifier: String, targetMillilitres: Int?,
        consumedMillilitres: Int, lastIntakeAt: Date?, updatedAt: Date
    ) throws {
        schemaVersion = 1
        dayStart = day.start
        dayEnd = day.end
        self.timeZoneIdentifier = timeZoneIdentifier
        self.targetMillilitres = targetMillilitres
        self.consumedMillilitres = consumedMillilitres
        self.lastIntakeAt = lastIntakeAt
        self.updatedAt = updatedAt
        try validate()
    }

    var remainingMillilitres: Int? {
        targetMillilitres.map { max($0 - consumedMillilitres, 0) }
    }

    var completionFraction: Double {
        guard let targetMillilitres else { return 0 }
        return min(Double(consumedMillilitres) / Double(targetMillilitres), 1)
    }

    func isCurrent(at date: Date, calendar: Calendar) -> Bool {
        date >= dayStart && date < dayEnd &&
        calendar.timeZone.identifier == timeZoneIdentifier &&
        calendar.dateInterval(of: .day, for: date)?.start == dayStart
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw Failure.unsupportedVersion }
        guard dayStart < dayEnd, updatedAt >= dayStart, updatedAt < dayEnd,
              TimeZone(identifier: timeZoneIdentifier) != nil,
              consumedMillilitres >= 0 else { throw Failure.invalidProgress }
        if let targetMillilitres {
            guard targetMillilitres > 0 else { throw Failure.invalidProgress }
        } else {
            guard consumedMillilitres == 0, lastIntakeAt == nil else { throw Failure.invalidProgress }
        }
        if let lastIntakeAt {
            guard lastIntakeAt >= dayStart, lastIntakeAt <= updatedAt else { throw Failure.invalidProgress }
        }
    }

    enum Failure: Error {
        case unsupportedVersion
        case invalidProgress
    }
}

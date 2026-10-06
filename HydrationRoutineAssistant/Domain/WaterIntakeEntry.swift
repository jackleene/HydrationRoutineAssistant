import Foundation

struct WaterIntakeEntry: Identifiable, Equatable, Sendable {
    // This limit applies to one log entry, not to the total daily intake.
    static let supportedAmountMillilitres = 1...1_000

    let id: UUID
    let goalID: UUID
    let amountMillilitres: Int
    let recordedAt: Date

    /// Supply `now` explicitly so time validation can use a fixed clock in tests.
    init(
        id: UUID = UUID(),
        goalID: UUID,
        amountMillilitres: Int,
        recordedAt: Date,
        now: Date
    ) throws {
        guard Self.supportedAmountMillilitres.contains(amountMillilitres) else {
            throw ValidationError.amountOutsideSupportedRange
        }
        guard recordedAt <= now else {
            throw ValidationError.recordedInFuture
        }
        self.id = id
        self.goalID = goalID
        self.amountMillilitres = amountMillilitres
        self.recordedAt = recordedAt
    }

    enum ValidationError: LocalizedError, Equatable {
        case amountOutsideSupportedRange
        case recordedInFuture

        var errorDescription: String? {
            switch self {
            case .amountOutsideSupportedRange:
                "A water intake record must contain between 1 and 1000 mL."
            case .recordedInFuture:
                "The drinking time is in the future."
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .amountOutsideSupportedRange:
                "Enter the amount you drank within this range, then save again."
            case .recordedInFuture:
                "Choose the current time or an earlier drinking time, then save again."
            }
        }
    }
}

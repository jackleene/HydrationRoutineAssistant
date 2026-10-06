import Foundation

struct HydrationGoal: Identifiable, Equatable, Sendable {
    // These bounds define accepted app input, not a recommended daily water intake.
    static let supportedTargetMillilitres = 500...5_000

    let id: UUID
    /// This timestamp is not normalized to midnight. Interpret its day using the
    /// calendar supplied to `HydrationProgress`.
    let date: Date
    let targetMillilitres: Int

    init(id: UUID = UUID(), date: Date, targetMillilitres: Int) throws {
        guard Self.supportedTargetMillilitres.contains(targetMillilitres) else {
            throw ValidationError.targetOutsideSupportedRange
        }
        self.id = id
        self.date = date
        self.targetMillilitres = targetMillilitres
    }

    enum ValidationError: LocalizedError, Equatable {
        case targetOutsideSupportedRange

        var errorDescription: String? {
            "The daily water target must be between 500 and 5000 mL."
        }

        var recoverySuggestion: String? {
            "Enter a target within this range, then save your daily goal again."
        }
    }
}

import Foundation
import Testing
import UIKit
@testable import HydrationRoutineAssistant

struct HydrationRoutineAssistantTests {
    @Test("The app bundles its hydration accent color")
    @MainActor
    func hydrationAccentColorIsBundled() throws {
        let appBundle = Bundle.main
        #expect(appBundle.bundleIdentifier == "com.mingchen.HydrationRoutineAssistant")
        let accentColor = try #require(UIColor(named: "AccentColor", in: appBundle, compatibleWith: nil))
        #expect(accentColor.cgColor.alpha == 1)
    }
}

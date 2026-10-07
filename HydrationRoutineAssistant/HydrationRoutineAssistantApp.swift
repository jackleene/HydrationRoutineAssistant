import SwiftUI

@main
struct HydrationRoutineAssistantApp: App {
    @State private var launcher = HydrationLaunchViewModel(loader: HydrationComposition.makeWorkspace)

    var body: some Scene {
        WindowGroup {
            ContentView(launcher: launcher)
        }
    }
}

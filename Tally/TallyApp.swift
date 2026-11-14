import SwiftUI
import SwiftData

@main
struct TallyApp: App {
    private let container: ModelContainer = {
        do {
            return try ModelContainer(for: MacroEntry.self, MacroGoal.self, SavedFood.self,
                                      configurations: ModelConfiguration(cloudKitDatabase: .none))
        } catch { fatalError("Could not open Tally's local storage: \(error)") }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(MacroTheme.accent)
                .font(MacroTheme.bodyFont)
        }
        .modelContainer(container)
    }
}

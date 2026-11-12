import SwiftUI
import SwiftData

@main
struct TallyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(MacroTheme.accent)
                .font(MacroTheme.bodyFont)
        }
        .modelContainer(for: [MacroEntry.self, MacroGoal.self, SavedFood.self])
    }
}

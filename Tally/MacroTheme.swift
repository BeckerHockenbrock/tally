import SwiftUI
import UIKit
import SwiftData

enum MacroTheme {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let text = Color.primary
    static let secondary = Color.secondary
    static let muted = Color.secondary
    static let line = Color(uiColor: .separator)
    static let accent = Color.blue
    static let calories = Color.orange
    static let protein = Color.blue
    static let carbs = Color.teal
    static let fat = Color.purple
    static let bodyFont = Font.body
    static let labelFont = Font.subheadline

    static func formatAmount(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }
    
    static func formatCalories(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}

/// Shared guards protect charts even when an older store contains invalid values.
enum MacroProgress {
    static func fraction(consumed: Double, goal: Double) -> Double {
        guard consumed.isFinite, goal.isFinite, consumed >= 0, goal > 0 else { return 0 }
        return min(consumed / goal, 1)
    }

    static func percentLabel(consumed: Double, goal: Double) -> String {
        guard consumed.isFinite, goal.isFinite, consumed >= 0, goal > 0 else { return "0%" }
        let percent = (consumed / goal) * 100
        guard percent.isFinite, percent < 999_999 else { return "999999+%" }
        return "\(Int(percent))%"
    }
}

struct TallySectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.headline)
            .textCase(nil)
            .foregroundStyle(MacroTheme.text)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Native Button keeps cancel-by-dragging-away behavior; feedback begins at touch-down.
struct TallyPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1),
                       value: configuration.isPressed)
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}

private struct TallyPanelStyle: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(MacroTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(contrast == .increased ? MacroTheme.text.opacity(0.5) : .clear,
                                  lineWidth: 1)
            }
    }
}

private struct TallySheetStyle: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground {
                if reduceTransparency || contrast == .increased {
                    MacroTheme.surface
                } else {
                    Rectangle().fill(.regularMaterial)
                }
            }
    }
}

extension View {
    func tallyPanel() -> some View { modifier(TallyPanelStyle()) }
    func tallySheet() -> some View { modifier(TallySheetStyle()) }

    func tallyFormStyle() -> some View {
        background(MacroTheme.background)
            .font(MacroTheme.bodyFont)
            .tint(MacroTheme.accent)
    }
}


@MainActor
final class TallyFeedback: ObservableObject {
    @Published var message: String?
    @Published var deletedEntry: EntrySnapshot?
    @Published var successCount = 0
    private var dismissal: Task<Void, Never>?

    func confirm(_ text: String) {
        dismissal?.cancel()
        message = text
        successCount += 1
        UIAccessibility.post(notification: .announcement, argument: text)
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }

    func added(on date: Date) {
        confirm(Calendar.current.isDateInToday(date) ? "Added to Today" : "Added to " + date.formatted(date: .abbreviated, time: .omitted))
    }

    func delete(_ entry: MacroEntry, in context: ModelContext) throws {
        let snapshot = EntrySnapshot(entry)
        context.delete(entry)
        do { try context.save() }
        catch { context.rollback(); throw error }
        deletedEntry = snapshot
        UIAccessibility.post(notification: .announcement, argument: "Entry deleted. Undo available.")
    }

    func undo(in context: ModelContext) throws {
        guard let deletedEntry else { return }
        context.insert(deletedEntry.restore())
        do { try context.save() }
        catch { context.rollback(); throw error }
        self.deletedEntry = nil
        confirm("Entry restored")
    }
}

struct TallyFeedbackBanner: View {
    @EnvironmentObject private var feedback: TallyFeedback
    @Environment(\.modelContext) private var context
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 8) {
            if let message = feedback.message {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16).tallyPanel()
            }
            if feedback.deletedEntry != nil {
                ViewThatFits(in: .horizontal) {
                    HStack { Text("Entry deleted"); Spacer(); undoButton; closeButton }
                    VStack(alignment: .leading) {
                        Text("Entry deleted")
                        HStack { undoButton; Spacer(); closeButton }
                    }
                }
                .font(.subheadline.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 4).tallyPanel()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, feedback.message != nil || feedback.deletedEntry != nil ? 8 : 0)
        .frame(maxWidth: 640)
        .sensoryFeedback(.success, trigger: feedback.successCount)
        .alert("Could Not Restore Entry", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private var undoButton: some View {
        Button("Undo") {
            do { try feedback.undo(in: context) }
            catch { errorMessage = error.localizedDescription }
        }.frame(minWidth: 44, minHeight: 44)
    }
    private var closeButton: some View {
        Button { feedback.deletedEntry = nil } label: {
            Image(systemName: "xmark").frame(width: 44, height: 44)
        }.accessibilityLabel("Dismiss undo")
    }
}

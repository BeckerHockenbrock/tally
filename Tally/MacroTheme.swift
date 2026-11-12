import SwiftUI
import UIKit

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

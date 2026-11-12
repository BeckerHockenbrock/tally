import SwiftUI

struct EnergySummaryView: View {
    let consumed: Double
    let goal: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 48

    private var progress: Double { MacroProgress.fraction(consumed: consumed, goal: goal) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Calories", systemImage: "flame.fill")
                .font(.headline)
                .foregroundStyle(MacroTheme.calories)

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(MacroTheme.formatCalories(consumed))
                        .font(.system(size: amountSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1), value: consumed)
                        .accessibilityLabel("\(MacroTheme.formatCalories(consumed)) calories consumed")
                    Text("of \(MacroTheme.formatCalories(goal)) kcal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if !dynamicTypeSize.isAccessibilitySize {
                    ZStack {
                        Circle().stroke(MacroTheme.calories.opacity(0.15), lineWidth: 9)
                        Circle().trim(from: 0, to: progress)
                            .stroke(MacroTheme.calories, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1), value: progress)
                        Text(MacroProgress.percentLabel(consumed: consumed, goal: goal))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    .frame(width: 84, height: 84)
                    .padding(5)
                    .accessibilityHidden(true)
                }
            }

            Label("\(MacroTheme.formatCalories(abs(goal - consumed))) kcal \(consumed > goal ? "over goal" : "remaining")",
                  systemImage: consumed > goal ? "plus.circle" : "target")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(consumed > goal ? Color.red : Color.secondary)
        }
        .padding(20)
        .tallyPanel()
    }
}

struct MacroProgressBarCard: View {
    let title: String
    let consumed: Double
    let goal: Double
    let color: Color
    let icon: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var progress: Double { MacroProgress.fraction(consumed: consumed, goal: goal) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    macroLabel
                    amountLabel
                }
            } else {
                HStack(spacing: 12) {
                    macroLabel
                    Spacer(minLength: 8)
                    amountLabel
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.14))
                    Capsule().fill(color).frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 5)
            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1), value: progress)
        }
        .padding(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(MacroTheme.formatAmount(consumed)) grams of \(MacroTheme.formatAmount(goal)) grams, \(MacroProgress.percentLabel(consumed: consumed, goal: goal))")
    }

    private var macroLabel: some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
    }

    private var amountLabel: some View {
        Text("\(MacroTheme.formatAmount(consumed)) / \(MacroTheme.formatAmount(goal)) g")
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}

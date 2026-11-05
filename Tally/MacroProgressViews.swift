import SwiftUI

struct CalorieRingView: View {
    let consumed: Double
    let goal: Double
    
    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(max(consumed / goal, 0), 1.0)
    }
    
    private var isOverGoal: Bool {
        consumed > goal && goal > 0
    }
    
    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(MacroTheme.calories.opacity(0.18), lineWidth: 14)
            
            // Progress arc
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            MacroTheme.calories.opacity(0.8),
                            MacroTheme.calories
                        ]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.75), value: progress)
            
            // Inner content
            VStack(spacing: 2) {
                Text(MacroTheme.formatCalories(consumed))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Text("of \(MacroTheme.formatCalories(goal)) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
                
                if isOverGoal {
                    Text("+\(MacroTheme.formatCalories(consumed - goal)) over")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.12), in: Capsule())
                        .padding(.top, 2)
                } else {
                    let remaining = max(0, goal - consumed)
                    Text("\(MacroTheme.formatCalories(remaining)) left")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(MacroTheme.calories)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(MacroTheme.calories.opacity(0.12), in: Capsule())
                        .padding(.top, 2)
                }
            }
        }
        .frame(width: 160, height: 160)
        .padding(8)
    }
}

struct MacroProgressBarCard: View {
    let title: String
    let consumed: Double
    let goal: Double
    let color: Color
    let icon: String
    
    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(max(consumed / goal, 0), 1.0)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(MacroTheme.formatAmount(consumed))/\(MacroTheme.formatAmount(goal))g")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
            }
            
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.15))
                        .frame(height: 8)
                    
                    Capsule()
                        .fill(color)
                        .frame(width: max(0, proxy.size.width * CGFloat(progress)), height: 8)
                        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: progress)
                }
            }
            .frame(height: 8)
            
            HStack {
                let percent = goal > 0 ? Int((consumed / goal) * 100) : 0
                Text("\(percent)%")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
                let remaining = goal - consumed
                if remaining > 0 {
                    Text("\(MacroTheme.formatAmount(remaining))g left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if remaining < 0 {
                    Text("\(MacroTheme.formatAmount(abs(remaining)))g over")
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else {
                    Text("Goal met")
                        .font(.caption2)
                        .foregroundStyle(color)
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

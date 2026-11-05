import SwiftUI
import SwiftData

struct GoalsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var goals: [MacroGoal]
    
    @State private var calorieText: String = ""
    @State private var proteinText: String = ""
    @State private var carbsText: String = ""
    @State private var fatText: String = ""
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case calories, protein, carbs, fat
    }
    
    private var currentGoal: MacroGoal? {
        goals.first
    }
    
    private var caloriesFromMacros: Double {
        let p = parseInput(proteinText)
        let c = parseInput(carbsText)
        let f = parseInput(fatText)
        return (p * 4.0) + (c * 4.0) + (f * 9.0)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Label {
                            Text("Daily Calories")
                        } icon: {
                            Image(systemName: "flame.circle.fill")
                                .foregroundStyle(MacroTheme.calories)
                        }
                        Spacer()
                        TextField("2000", text: $calorieText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .calories)
                            .frame(maxWidth: 100)
                        Text("kcal")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Energy Target")
                } footer: {
                    if caloriesFromMacros > 0 {
                        Button {
                            calorieText = MacroTheme.formatCalories(caloriesFromMacros)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "wand.and.stars")
                                Text("Match macros: \(MacroTheme.formatCalories(caloriesFromMacros)) kcal")
                            }
                            .font(.footnote)
                        }
                        .padding(.top, 4)
                    }
                }
                
                Section {
                    HStack {
                        Label {
                            Text("Protein")
                        } icon: {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(MacroTheme.protein)
                        }
                        Spacer()
                        TextField("140", text: $proteinText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .protein)
                            .frame(maxWidth: 90)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Label {
                            Text("Carbs")
                        } icon: {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(MacroTheme.carbs)
                        }
                        Spacer()
                        TextField("200", text: $carbsText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .carbs)
                            .frame(maxWidth: 90)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Label {
                            Text("Fat")
                        } icon: {
                            Image(systemName: "drop.fill")
                                .foregroundStyle(MacroTheme.fat)
                        }
                        Spacer()
                        TextField("65", text: $fatText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .fat)
                            .frame(maxWidth: 90)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Daily Macro Targets")
                } footer: {
                    Text("Macro targets determine the progress bars on your dashboard.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Daily Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveGoals()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .onAppear {
                loadCurrentGoals()
            }
        }
    }
    
    private func parseInput(_ text: String) -> Double {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0
    }
    
    private func loadCurrentGoals() {
        if let existing = currentGoal {
            calorieText = MacroTheme.formatCalories(existing.calories)
            proteinText = MacroTheme.formatAmount(existing.protein)
            carbsText = MacroTheme.formatAmount(existing.carbs)
            fatText = MacroTheme.formatAmount(existing.fat)
        } else {
            calorieText = "2000"
            proteinText = "140"
            carbsText = "200"
            fatText = "65"
        }
    }
    
    private func saveGoals() {
        let cal = max(100, parseInput(calorieText))
        let p = max(0, parseInput(proteinText))
        let c = max(0, parseInput(carbsText))
        let f = max(0, parseInput(fatText))
        
        if let existing = currentGoal {
            existing.calories = cal
            existing.protein = p
            existing.carbs = c
            existing.fat = f
            existing.updatedAt = Date()
        } else {
            let newGoal = MacroGoal(
                calories: cal,
                protein: p,
                carbs: c,
                fat: f,
                updatedAt: Date()
            )
            modelContext.insert(newGoal)
        }
        
        try? modelContext.save()
        dismiss()
    }
}

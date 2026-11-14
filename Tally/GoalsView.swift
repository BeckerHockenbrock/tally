import SwiftUI
import SwiftData

struct GoalsView: View {
    var isTab = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var goals: [MacroGoal]

    @State private var saveError: String?
    @State private var showingSaved = false
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

    private var isFormValid: Bool {
        GoalInput.value(calorieText, calories: true) != nil &&
        [proteinText, carbsText, fatText].allSatisfy { GoalInput.value($0) != nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
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
                    TallySectionLabel(text: "Energy Target")
                } footer: {
                    if caloriesFromMacros > 0 {
                        Button {
                            calorieText = GoalInput.editingText(caloriesFromMacros)
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
                    TallySectionLabel(text: "Daily Macro Targets")
                } footer: {
                    Text("Macro targets determine the progress bars on your dashboard. Enter zero or 0.1–100,000 g per macro, and 100–1,000,000 calories.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                }
                .listRowBackground(MacroTheme.surface)
            }
            .tallyFormStyle()
            .navigationTitle("Daily Goals")

            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isTab {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveGoals()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isFormValid)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .alert("Could Not Save Goals", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(saveError ?? "") }
            .safeAreaInset(edge: .bottom) {
                if showingSaved {
                    Label("Goals saved", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium)).padding(16)
                        .frame(maxWidth: .infinity).background(MacroTheme.surface)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .sensoryFeedback(.success, trigger: showingSaved) { _, isSaved in isSaved }
            .task(id: showingSaved) {
                guard showingSaved else { return }
                UIAccessibility.post(notification: .announcement, argument: "Goals saved")
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                showingSaved = false
            }
            .onChange(of: calorieText + proteinText + carbsText + fatText) { _, _ in showingSaved = false }
            .onAppear {
                loadCurrentGoals()
            }
        }
    }

    private func parseInput(_ text: String) -> Double {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite, value >= 0, value <= 1_000_000 else { return 0 }
        return value
    }

    private func loadCurrentGoals() {
        if let existing = currentGoal {
            calorieText = GoalInput.editingText(existing.calories)
            proteinText = GoalInput.editingText(existing.protein)
            carbsText = GoalInput.editingText(existing.carbs)
            fatText = GoalInput.editingText(existing.fat)
        } else {
            calorieText = "2000"
            proteinText = "140"
            carbsText = "200"
            fatText = "65"
        }
    }

    private func saveGoals() {
        guard let cal = GoalInput.value(calorieText, calories: true),
              let p = GoalInput.value(proteinText),
              let c = GoalInput.value(carbsText),
              let f = GoalInput.value(fatText) else { return }

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

        do {
            try modelContext.save()
            if isTab { showingSaved = true } else { dismiss() }
        }
        catch { modelContext.rollback(); saveError = error.localizedDescription }
    }
}

import SwiftUI
import SwiftData

struct AddEditEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    var entryToEdit: MacroEntry?
    var initialDate: Date
    
    @State private var name: String = ""
    @State private var proteinText: String = ""
    @State private var carbsText: String = ""
    @State private var fatText: String = ""
    @State private var entryDate: Date = Date()
    @State private var isShowingDeleteConfirm: Bool = false
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case name, protein, carbs, fat
    }
    
    init(entryToEdit: MacroEntry? = nil, initialDate: Date = Date()) {
        self.entryToEdit = entryToEdit
        self.initialDate = initialDate
    }
    
    private var proteinValue: Double {
        parseInput(proteinText)
    }
    
    private var carbsValue: Double {
        parseInput(carbsText)
    }
    
    private var fatValue: Double {
        parseInput(fatText)
    }
    
    private var calculatedCalories: Double {
        (proteinValue * 4.0) + (carbsValue * 4.0) + (fatValue * 9.0)
    }
    
    private var isFormValid: Bool {
        proteinValue > 0 || carbsValue > 0 || fatValue > 0
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Entry name (e.g., Lunch, Protein Shake)", text: $name)
                        .focused($focusedField, equals: .name)
                    
                    DatePicker("Date & Time", selection: $entryDate, displayedComponents: [.date, .hourAndMinute])
                } header: {
                    Text("Details")
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
                        TextField("0", text: $proteinText)
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
                        TextField("0", text: $carbsText)
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
                        TextField("0", text: $fatText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .fat)
                            .frame(maxWidth: 90)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Macros (Grams)")
                } footer: {
                    Text("4 cal/g protein • 4 cal/g carbs • 9 cal/g fat")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Total Calories")
                                .font(.headline)
                            Spacer()
                            Text(MacroTheme.formatCalories(calculatedCalories))
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(MacroTheme.calories)
                            Text("kcal")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        // Mini breakdown bar
                        if calculatedCalories > 0 {
                            GeometryReader { proxy in
                                let total = max(1.0, calculatedCalories)
                                let pWidth = proxy.size.width * CGFloat((proteinValue * 4.0) / total)
                                let cWidth = proxy.size.width * CGFloat((carbsValue * 4.0) / total)
                                let fWidth = proxy.size.width * CGFloat((fatValue * 9.0) / total)
                                
                                HStack(spacing: 2) {
                                    if pWidth > 0 {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(MacroTheme.protein)
                                            .frame(width: max(2, pWidth))
                                    }
                                    if cWidth > 0 {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(MacroTheme.carbs)
                                            .frame(width: max(2, cWidth))
                                    }
                                    if fWidth > 0 {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(MacroTheme.fat)
                                            .frame(width: max(2, fWidth))
                                    }
                                }
                            }
                            .frame(height: 8)
                            .clipShape(Capsule())
                            
                            HStack {
                                MacroPill(label: "Protein", calories: proteinValue * 4, color: MacroTheme.protein)
                                Spacer()
                                MacroPill(label: "Carbs", calories: carbsValue * 4, color: MacroTheme.carbs)
                                Spacer()
                                MacroPill(label: "Fat", calories: fatValue * 9, color: MacroTheme.fat)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Calculated Energy")
                }
                
                if entryToEdit != nil {
                    Section {
                        Button(role: .destructive) {
                            isShowingDeleteConfirm = true
                        } label: {
                            HStack {
                                Spacer()
                                Label("Delete Entry", systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(entryToEdit == nil ? "Add Entry" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(entryToEdit == nil ? "Save" : "Update") {
                        saveEntry()
                    }
                    .disabled(!isFormValid)
                    .fontWeight(.semibold)
                }
                
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .confirmationDialog(
                "Delete Entry",
                isPresented: $isShowingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let entry = entryToEdit {
                        modelContext.delete(entry)
                        try? modelContext.save()
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this macro entry?")
            }
            .onAppear {
                populateInitialData()
            }
        }
    }
    
    private func parseInput(_ text: String) -> Double {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0
    }
    
    private func populateInitialData() {
        if let entry = entryToEdit {
            name = entry.name
            proteinText = entry.protein > 0 ? MacroTheme.formatAmount(entry.protein) : ""
            carbsText = entry.carbs > 0 ? MacroTheme.formatAmount(entry.carbs) : ""
            fatText = entry.fat > 0 ? MacroTheme.formatAmount(entry.fat) : ""
            entryDate = entry.date
        } else {
            let calendar = Calendar.current
            if calendar.isDateInToday(initialDate) {
                entryDate = Date()
            } else {
                let nowComponents = calendar.dateComponents([.hour, .minute, .second], from: Date())
                entryDate = calendar.date(bySettingHour: nowComponents.hour ?? 12,
                                         minute: nowComponents.minute ?? 0,
                                         second: nowComponents.second ?? 0,
                                         of: initialDate) ?? initialDate
            }
            focusedField = .name
        }
    }
    
    private func saveEntry() {
        let p = proteinValue
        let c = carbsValue
        let f = fatValue
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let entry = entryToEdit {
            entry.name = trimmedName
            entry.protein = p
            entry.carbs = c
            entry.fat = f
            entry.date = entryDate
        } else {
            let newEntry = MacroEntry(
                name: trimmedName,
                protein: p,
                carbs: c,
                fat: f,
                date: entryDate
            )
            modelContext.insert(newEntry)
        }
        
        try? modelContext.save()
        dismiss()
    }
}

private struct MacroPill: View {
    let label: String
    let calories: Double
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .foregroundStyle(.secondary)
            Text("\(MacroTheme.formatCalories(calories)) kcal")
                .foregroundStyle(.primary)
                .fontWeight(.medium)
        }
    }
}

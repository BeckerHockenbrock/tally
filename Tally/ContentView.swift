import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MacroEntry.date, order: .reverse) private var allEntries: [MacroEntry]
    @Query private var goals: [MacroGoal]
    
    @State private var selectedDate: Date = Date()
    @State private var isShowingAddEntrySheet: Bool = false
    @State private var entryToEdit: MacroEntry? = nil
    @State private var isShowingGoalsSheet: Bool = false
    @State private var isShowingDatePickerSheet: Bool = false
    @State private var entryToDelete: MacroEntry? = nil
    @State private var isShowingDeleteConfirmation: Bool = false
    
    private var activeGoal: MacroGoal {
        goals.first ?? MacroGoal()
    }
    
    private var dayEntries: [MacroEntry] {
        let calendar = Calendar.current
        return allEntries.filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
    }
    
    private var totalCalories: Double {
        dayEntries.reduce(0) { $0 + $1.calories }
    }
    
    private var totalProtein: Double {
        dayEntries.reduce(0) { $0 + $1.protein }
    }
    
    private var totalCarbs: Double {
        dayEntries.reduce(0) { $0 + $1.carbs }
    }
    
    private var totalFat: Double {
        dayEntries.reduce(0) { $0 + $1.fat }
    }
    
    private var isSelectedDateToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(spacing: 18) {
                        // Date Navigation Header
                        dateNavigator
                        
                        // Energy Dashboard Hero Card
                        energyDashboardCard
                        
                        // Macro Targets Cards
                        macroCardsGrid
                        
                        // Daily History Section
                        dailyHistorySection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 90) // Extra padding for the floating action button
                }
                .background(Color(uiColor: .systemGroupedBackground))
                
                // Prominent Floating "+" Button
                floatingAddButton
            }
            .navigationTitle("Tally")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingGoalsSheet = true
                    } label: {
                        Label("Goals", systemImage: "target")
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAddEntrySheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(MacroTheme.calories)
                    }
                }
            }
            .sheet(isPresented: $isShowingAddEntrySheet) {
                AddEditEntryView(initialDate: selectedDate)
            }
            .sheet(item: $entryToEdit) { entry in
                AddEditEntryView(entryToEdit: entry, initialDate: entry.date)
            }
            .sheet(isPresented: $isShowingGoalsSheet) {
                GoalsView()
            }
            .sheet(isPresented: $isShowingDatePickerSheet) {
                datePickerSheet
            }
            .confirmationDialog(
                "Delete Entry",
                isPresented: $isShowingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let entry = entryToDelete {
                        withAnimation {
                            modelContext.delete(entry)
                            try? modelContext.save()
                        }
                    }
                    entryToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    entryToDelete = nil
                }
            } message: {
                Text("Are you sure you want to delete this macro entry?")
            }
            .onAppear {
                ensureInitialGoalExists()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var dateNavigator: some View {
        HStack {
            Button {
                changeDay(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .padding(8)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
            }
            
            Spacer()
            
            Button {
                isShowingDatePickerSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption)
                    Text(formattedSelectedDate)
                        .font(.headline)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            }
            
            Spacer()
            
            Button {
                changeDay(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .padding(8)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
            }
        }
        .overlay {
            if !isSelectedDateToday {
                HStack {
                    Spacer()
                    Button("Today") {
                        withAnimation {
                            selectedDate = Date()
                        }
                    }
                    .font(.caption.bold())
                    .foregroundStyle(MacroTheme.calories)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(MacroTheme.calories.opacity(0.12), in: Capsule())
                    .offset(x: 0, y: 34)
                    Spacer()
                }
            }
        }
        .padding(.bottom, !isSelectedDateToday ? 20 : 0)
    }
    
    private var energyDashboardCard: some View {
        VStack(spacing: 12) {
            Text("Energy Summary")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            CalorieRingView(consumed: totalCalories, goal: activeGoal.calories)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    
    private var macroCardsGrid: some View {
        VStack(spacing: 10) {
            MacroProgressBarCard(
                title: "Protein",
                consumed: totalProtein,
                goal: activeGoal.protein,
                color: MacroTheme.protein,
                icon: "flame.fill"
            )
            
            MacroProgressBarCard(
                title: "Carbohydrates",
                consumed: totalCarbs,
                goal: activeGoal.carbs,
                color: MacroTheme.carbs,
                icon: "bolt.fill"
            )
            
            MacroProgressBarCard(
                title: "Fat",
                consumed: totalFat,
                goal: activeGoal.fat,
                color: MacroTheme.fat,
                icon: "drop.fill"
            )
        }
    }
    
    private var dailyHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Entries")
                    .font(.title3.bold())
                
                Spacer()
                
                if !dayEntries.isEmpty {
                    Text("\(dayEntries.count) \(dayEntries.count == 1 ? "entry" : "entries")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 6)
            
            if dayEntries.isEmpty {
                emptyDayView
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(dayEntries) { entry in
                        entryRow(entry)
                    }
                }
            }
        }
    }
    
    private func entryRow(_ entry: MacroEntry) -> some View {
        HStack(spacing: 14) {
            Button {
                entryToEdit = entry
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        Text("\(MacroTheme.formatCalories(entry.calories)) kcal")
                            .font(.subheadline.bold())
                            .foregroundStyle(MacroTheme.calories)
                    }
                    
                    HStack(spacing: 10) {
                        Text(entry.date.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        macroMiniTag(label: "P", amount: entry.protein, color: MacroTheme.protein)
                        macroMiniTag(label: "C", amount: entry.carbs, color: MacroTheme.carbs)
                        macroMiniTag(label: "F", amount: entry.fat, color: MacroTheme.fat)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Menu {
                Button {
                    entryToEdit = entry
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                
                Button(role: .destructive) {
                    entryToDelete = entry
                    isShowingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu {
            Button {
                entryToEdit = entry
            } label: {
                Label("Edit Entry", systemImage: "pencil")
            }
            
            Button(role: .destructive) {
                entryToDelete = entry
                isShowingDeleteConfirmation = true
            } label: {
                Label("Delete Entry", systemImage: "trash")
            }
        }
    }
    
    private func macroMiniTag(label: String, amount: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(color)
            Text("\(MacroTheme.formatAmount(amount))g")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
    
    private var emptyDayView: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            
            Text("No entries for this day")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            
            Button {
                isShowingAddEntrySheet = true
            } label: {
                Text("Log Macros")
                    .font(.footnote.bold())
                    .foregroundStyle(MacroTheme.calories)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(MacroTheme.calories.opacity(0.12), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    
    private var floatingAddButton: some View {
        Button {
            isShowingAddEntrySheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.title2.bold())
                Text("Add Entry")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(MacroTheme.calories)
                    .shadow(color: MacroTheme.calories.opacity(0.4), radius: 10, x: 0, y: 5)
            )
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }
    
    private var datePickerSheet: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .padding()
                
                Spacer()
            }
            .navigationTitle("Jump to Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isShowingDatePickerSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    // MARK: - Helpers
    
    private var formattedSelectedDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDate) {
            return "Today"
        } else if calendar.isDateInYesterday(selectedDate) {
            return "Yesterday"
        } else if calendar.isDateInTomorrow(selectedDate) {
            return "Tomorrow"
        } else {
            return selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
    }
    
    private func changeDay(by delta: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: delta, to: selectedDate) {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDate = newDate
            }
        }
    }
    
    private func ensureInitialGoalExists() {
        if goals.isEmpty {
            let defaultGoal = MacroGoal()
            modelContext.insert(defaultGoal)
            try? modelContext.save()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [MacroEntry.self, MacroGoal.self], inMemory: true)
}

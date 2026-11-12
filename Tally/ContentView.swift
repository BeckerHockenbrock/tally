import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDate = Date()
    @State private var followsToday = true
    @State private var calendar = Calendar.current

    var body: some View {
        DiaryDayView(selectedDate: $selectedDate, calendar: calendar)
            .environment(\.calendar, calendar)
            .onChange(of: selectedDate) { _, date in
                followsToday = calendar.isDateInToday(date)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshDay() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshDay() }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in refreshDay() }
    }

    private func refreshDay() {
        let updatedCalendar = Calendar.current
        if followsToday {
            selectedDate = Date()
        } else {
            // Keep the chosen calendar day when the device changes time zone.
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: selectedDate)
            selectedDate = updatedCalendar.date(from: components) ?? selectedDate
        }
        calendar = updatedCalendar
    }
}

private struct DiaryDayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var contentSpacing = 20

    @Environment(\.modelContext) private var modelContext
    @Query private var dayEntries: [MacroEntry]
    @Binding var selectedDate: Date

    init(selectedDate: Binding<Date>, calendar: Calendar) {
        _selectedDate = selectedDate
        _dayEntries = Query(DiaryDates.descriptor(for: selectedDate.wrappedValue, calendar: calendar))
    }
    @Query private var goals: [MacroGoal]
    
    @State private var saveError: String?
    @State private var isShowingAddEntrySheet: Bool = false
    @State private var entryToEdit: MacroEntry? = nil
    @State private var isShowingGoalsSheet: Bool = false
    @State private var isShowingDatePickerSheet: Bool = false
    @State private var entryToDelete: MacroEntry? = nil
    @State private var isShowingDeleteConfirmation: Bool = false
    
    private var activeGoal: MacroGoal {
        goals.first ?? MacroGoal()
    }
    
    private var isSelectedDateToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }
    
    var body: some View {
        let totals = DiaryTotals(entries: dayEntries)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: contentSpacing) {
                    dateNavigator
                    energyDashboardCard(totalCalories: totals.calories)
                    VStack(alignment: .leading, spacing: 12) {
                        TallySectionLabel(text: "Macros")
                        macroCardsGrid(totals: totals)
                    }
                    dailyHistorySection
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .background(MacroTheme.background)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                addFoodButton
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
            .navigationTitle("Tally")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isShowingGoalsSheet = true } label: {
                        Label("Goals", systemImage: "target")
                            .font(MacroTheme.labelFont)
                    }
                    .tint(MacroTheme.accent)
                    .accessibilityLabel("Edit daily goals")
                }
            }
            .sheet(isPresented: $isShowingAddEntrySheet) {
                FoodEntryView(initialDate: selectedDate, followsToday: isSelectedDateToday)
                    .tallySheet()
            }
            .sheet(item: $entryToEdit) { entry in
                AddEditEntryView(entryToEdit: entry, initialDate: entry.date)
                    .tallySheet()
            }
            .sheet(isPresented: $isShowingGoalsSheet) {
                GoalsView().tallySheet()
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
                        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 1)) {
                            modelContext.delete(entry)
                            do { try modelContext.save() }
                            catch { modelContext.rollback(); saveError = error.localizedDescription }
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
            .alert("Could Not Save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(saveError ?? "") }
            .onAppear {
                ensureInitialGoalExists()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var dateNavigator: some View {
        VStack(spacing: 12) {
            HStack {
                Button { changeDay(by: -1) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Previous day")
                Spacer(minLength: 4)
                Button { isShowingDatePickerSheet = true } label: {
                    VStack(spacing: 4) {
                        Text(formattedSelectedDate).font(.headline)
                        Text(selectedDate.formatted(.dateTime.month(.wide).day().year()))
                            .font(MacroTheme.labelFont).foregroundStyle(MacroTheme.muted)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("Choose date, \(formattedSelectedDate)")
                Spacer(minLength: 4)
                Button { changeDay(by: 1) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Next day")
            }
            .buttonStyle(TallyPressStyle())
            if !isSelectedDateToday {
                Button("Return to today") { selectedDate = Date() }
                    .font(MacroTheme.labelFont).frame(minHeight: 44)
                    .buttonStyle(TallyPressStyle())
            }
        }
        .padding(8)
        .tallyPanel()
    }

    private func energyDashboardCard(totalCalories: Double) -> some View {
        EnergySummaryView(consumed: totalCalories, goal: activeGoal.calories)
    }

    private func macroCardsGrid(totals: DiaryTotals) -> some View {
        VStack(spacing: 0) {
            MacroProgressBarCard(
                title: "Protein",
                consumed: totals.protein,
                goal: activeGoal.protein,
                color: MacroTheme.protein,
                icon: "flame.fill"
            )
            
            Divider().padding(.leading, 16)
            MacroProgressBarCard(
                title: "Carbohydrates",
                consumed: totals.carbs,
                goal: activeGoal.carbs,
                color: MacroTheme.carbs,
                icon: "bolt.fill"
            )
            
            Divider().padding(.leading, 16)
            MacroProgressBarCard(
                title: "Fat",
                consumed: totals.fat,
                goal: activeGoal.fat,
                color: MacroTheme.fat,
                icon: "drop.fill"
            )
        }
        .tallyPanel()
    }
    
    private var dailyHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TallySectionLabel(text: "Food log")
                
                Spacer()
                
                if !dayEntries.isEmpty {
                    Text("\(dayEntries.count) \(dayEntries.count == 1 ? "entry" : "entries")")
                        .font(MacroTheme.labelFont)
                        .foregroundStyle(MacroTheme.muted)
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
                VStack(alignment: .leading, spacing: 8) {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.displayName).font(.headline)
                            Text("\(MacroTheme.formatCalories(entry.calories)) kcal").font(.subheadline.weight(.semibold))
                        }
                        Text(entry.date.formatted(date: .omitted, time: .shortened)).font(.caption)
                        VStack(alignment: .leading, spacing: 4) {
                            macroMiniTag(label: "Protein", amount: entry.protein, color: MacroTheme.protein)
                            macroMiniTag(label: "Carbs", amount: entry.carbs, color: MacroTheme.carbs)
                            macroMiniTag(label: "Fat", amount: entry.fat, color: MacroTheme.fat)
                        }
                    } else {
                        HStack {
                            Text(entry.displayName).font(.headline)
                            Spacer()
                            Text("\(MacroTheme.formatCalories(entry.calories)) kcal").font(.subheadline.weight(.semibold))
                        }
                        HStack(spacing: 10) {
                            Text(entry.date.formatted(date: .omitted, time: .shortened)).font(.caption)
                            macroMiniTag(label: "P", amount: entry.protein, color: MacroTheme.protein)
                            macroMiniTag(label: "C", amount: entry.carbs, color: MacroTheme.carbs)
                            macroMiniTag(label: "F", amount: entry.fat, color: MacroTheme.fat)
                        }
                        .foregroundStyle(MacroTheme.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(TallyPressStyle())

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
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(16)
        .tallyPanel()
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
        ContentUnavailableView("No food logged", systemImage: "fork.knife",
            description: Text("Add a meal or snack to start tracking this day."))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .tallyPanel()
    }

    private var addFoodButton: some View {
        Button { isShowingAddEntrySheet = true } label: {
            Label("Add Food", systemImage: "plus")
                .labelStyle(.titleAndIcon)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .accessibilityLabel("Add food entry")
    }

    private var datePickerSheet: some View {
        NavigationStack {
            ScrollView {
                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .padding()
                
            }
            .background(MacroTheme.background)
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
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .tallySheet()
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
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 1)) {
                selectedDate = newDate
            }
        }
    }
    
    private func ensureInitialGoalExists() {
        if goals.isEmpty {
            let defaultGoal = MacroGoal()
            modelContext.insert(defaultGoal)
            do { try modelContext.save() }
            catch { modelContext.rollback(); saveError = error.localizedDescription }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [MacroEntry.self, MacroGoal.self, SavedFood.self], inMemory: true)
}

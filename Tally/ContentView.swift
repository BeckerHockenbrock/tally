import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDate = Date()
    @State private var followsToday = true
    @State private var calendar = Calendar.current
    @State private var selectedTab = TallyTab.today
    @State private var showingAddMenu = false
    @State private var pendingFoodMode: FoodEntryMode?
    @State private var foodMode: FoodEntryMode?

    var body: some View {
        TabView(selection: $selectedTab) {
            DiaryDayView(selectedDate: $selectedDate, calendar: calendar)
                .tag(TallyTab.today)
                .tabItem { Label("Today", systemImage: "square.grid.2x2") }
                .toolbar(.hidden, for: .tabBar)
            DiaryDayView(selectedDate: $selectedDate, calendar: calendar, showsOverview: false)
                .tag(TallyTab.diary)
                .tabItem { Label("Diary", systemImage: "book.closed") }
                .toolbar(.hidden, for: .tabBar)
            FoodLibraryView { foodMode = .search }
                .tag(TallyTab.foods)
                .tabItem { Label("Foods", systemImage: "fork.knife") }
                .toolbar(.hidden, for: .tabBar)
            GoalsView(isTab: true)
                .tag(TallyTab.goals)
                .tabItem { Label("Goals", systemImage: "target") }
                .toolbar(.hidden, for: .tabBar)
        }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TallyBottomBar(selection: $selectedTab) { showingAddMenu = true }
            }
            .sheet(isPresented: $showingAddMenu, onDismiss: {
                foodMode = pendingFoodMode
                pendingFoodMode = nil
            }) {
                AddFoodMenu(date: foodDate) { mode in
                    pendingFoodMode = mode
                    showingAddMenu = false
                }
                .tallySheet()
            }
            .sheet(item: $foodMode) { mode in
                FoodEntryView(initialDate: foodDate, followsToday: calendar.isDateInToday(foodDate), initialMode: mode)
                    .tallySheet()
            }
            .environment(\.calendar, calendar)
            .onChange(of: selectedTab) { _, tab in
                if tab == .today { selectedDate = Date() }
            }
            .onChange(of: selectedDate) { _, date in
                followsToday = calendar.isDateInToday(date)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshDay() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshDay() }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in refreshDay() }
    }

    private var foodDate: Date {
        selectedTab == .today || selectedTab == .diary ? selectedDate : Date()
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

private enum TallyTab: String {
    case today, diary, foods, goals
}

private struct TallyBottomBar: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Binding var selection: TallyTab
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tab(.today, title: "Today", icon: "square.grid.2x2", selectedIcon: "square.grid.2x2.fill")
            tab(.diary, title: "Diary", icon: "book.closed", selectedIcon: "book.closed.fill")
            Button(action: onAdd) {
                VStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(MacroTheme.accent.gradient, in: Circle())
                        .shadow(color: MacroTheme.accent.opacity(0.24), radius: 9, y: 4)
                    Text("Add").font(.caption2.weight(.semibold)).foregroundStyle(MacroTheme.accent)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(TallyPressStyle())
            .accessibilityLabel("Add food")
            .accessibilityHint("Choose barcode scanning or food search")
            tab(.foods, title: "Foods", icon: "fork.knife", selectedIcon: "fork.knife")
            tab(.goals, title: "Goals", icon: "target", selectedIcon: "target")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background {
            if reduceTransparency { MacroTheme.surface.ignoresSafeArea(edges: .bottom) }
            else { Rectangle().fill(.bar).ignoresSafeArea(edges: .bottom) }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(MacroTheme.line.opacity(contrast == .increased ? 1 : 0.25)).frame(height: 0.5)
        }
    }

    private func tab(_ value: TallyTab, title: String, icon: String, selectedIcon: String) -> some View {
        Button { selection = value } label: {
            VStack(spacing: 4) {
                Image(systemName: selection == value ? selectedIcon : icon)
                    .font(.system(size: 21, weight: .medium))
                    .frame(width: 52, height: 38)
                    .background(selection == value ? MacroTheme.accent.opacity(0.1) : .clear, in: Capsule())
                Text(title).font(.caption2.weight(selection == value ? .semibold : .medium))
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(selection == value ? MacroTheme.accent : MacroTheme.secondary)
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(TallyPressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(selection == value ? [.isSelected] : [])
    }
}

private struct AddFoodMenu: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let date: Date
    let onSelect: (FoodEntryMode) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Add food").font(.system(.title, design: .rounded, weight: .bold))
                        Text(Calendar.current.isDateInToday(date) ? "What’s on your plate today?" : "For \(date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.subheadline.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(MacroTheme.secondary.opacity(0.1), in: Circle())
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Close add food menu")
                }
                option(.search, title: "Search foods", subtitle: "Find a food by name or brand", icon: "magnifyingglass", prominent: true)
                option(.barcode, title: "Scan a barcode", subtitle: "Use the nutrition on your package", icon: "barcode.viewfinder", prominent: false)
            }
            .padding(24)
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(350), .large])
    }

    private func option(_ mode: FoodEntryMode, title: String, subtitle: String, icon: String, prominent: Bool) -> some View {
        Button { onSelect(mode) } label: {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.title2.weight(.medium))
                    .frame(width: 48, height: 48)
                    .background(prominent ? .white.opacity(0.16) : MacroTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).opacity(prominent ? 0.9 : 0.7)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(prominent ? .white : MacroTheme.text)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if prominent { RoundedRectangle(cornerRadius: 22).fill(MacroTheme.accent.gradient) }
                else { RoundedRectangle(cornerRadius: 22).fill(MacroTheme.surface) }
            }
        }
        .buttonStyle(TallyPressStyle())
    }
}

private struct DiaryDayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var contentSpacing = 20

    @Environment(\.modelContext) private var modelContext
    @Query private var dayEntries: [MacroEntry]
    @Binding var selectedDate: Date
    let showsOverview: Bool

    init(selectedDate: Binding<Date>, calendar: Calendar, showsOverview: Bool = true) {
        _selectedDate = selectedDate
        _dayEntries = Query(DiaryDates.descriptor(for: selectedDate.wrappedValue, calendar: calendar))
        self.showsOverview = showsOverview
    }
    @Query private var goals: [MacroGoal]
    
    @State private var saveError: String?
    @State private var entryToEdit: MacroEntry? = nil
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
                    if showsOverview {
                        energyDashboardCard(totalCalories: totals.calories)
                        VStack(alignment: .leading, spacing: 12) {
                            TallySectionLabel(text: "Macros")
                            macroCardsGrid(totals: totals)
                        }
                    }
                    dailyHistorySection
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .background(MacroTheme.background)
            .navigationTitle(showsOverview ? "Tally" : "Diary")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $entryToEdit) { entry in
                AddEditEntryView(entryToEdit: entry, initialDate: entry.date)
                    .tallySheet()
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
                if showsOverview { ensureInitialGoalExists() }
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

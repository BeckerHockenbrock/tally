import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @StateObject private var feedback = TallyFeedback()
    @State private var todayDate = Date()
    @State private var startingFood: Food?
    @State private var cleanupError: String?
    @State private var selectedDate = Date()
    @State private var followsToday = true
    @State private var calendar = Calendar.current
    @State private var selectedTab = TallyTab.today
    @State private var showingAddMenu = false
    @State private var pendingFoodMode: FoodEntryMode?
    @State private var foodMode: FoodEntryMode?

    var body: some View {
        TabView(selection: $selectedTab) {
            DiaryDayView(selectedDate: $todayDate, calendar: calendar)
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
                VStack(spacing: 0) {
                    TallyFeedbackBanner()
                    TallyBottomBar(selection: $selectedTab) { showingAddMenu = true }
                }
            }
            .sheet(isPresented: $showingAddMenu, onDismiss: {
                foodMode = pendingFoodMode
                pendingFoodMode = nil
            }) {
                AddFoodMenu(date: foodDate, onRecent: { food in
                    startingFood = food
                    pendingFoodMode = .search
                    showingAddMenu = false
                }) { mode in
                    startingFood = nil
                    pendingFoodMode = mode
                    showingAddMenu = false
                }
                .tallySheet()
            }
            .sheet(item: $foodMode, onDismiss: { startingFood = nil }) { mode in
                FoodEntryView(initialDate: foodDate, followsToday: calendar.isDateInToday(foodDate), initialMode: mode, startingFood: startingFood)
                    .tallySheet()
            }
            .environmentObject(feedback)
            .environment(\.calendar, calendar)
            .task { cleanUpFoods() }
            .alert("Food Cleanup Failed", isPresented: Binding(get: { cleanupError != nil }, set: { if !$0 { cleanupError = nil } })) {
                Button("OK", role: .cancel) { }
            } message: { Text(cleanupError ?? "") }
            .onChange(of: selectedTab) { _, tab in
                if tab == .today { todayDate = Date() }
            }
            .onChange(of: selectedDate) { _, date in
                followsToday = calendar.isDateInToday(date)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshDay(); cleanUpFoods() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshDay() }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in refreshDay() }
    }

    private func cleanUpFoods() {
        do { try FoodStore(container: modelContext.container).removeExpired() }
        catch { cleanupError = "Unused scanned foods could not be removed. " + error.localizedDescription }
    }

    private var foodDate: Date {
        selectedTab == .diary ? selectedDate : Date()
    }

    private func refreshDay() {
        todayDate = Date()
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
    let onRecent: (Food) -> Void
    let onSelect: (FoodEntryMode) -> Void
    @Query(sort: \MacroEntry.date, order: .reverse) private var entries: [MacroEntry]
    @Query private var savedFoods: [SavedFood]

    private var recentFoods: [Food] { LocalFoodLibrary.recent(entries: entries, saved: savedFoods) }

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
                if !recentFoods.isEmpty {
                    TallySectionLabel(text: "Recent foods")
                    VStack(spacing: 0) {
                        ForEach(recentFoods) { food in
                            Button { onRecent(food) } label: {
                                HStack(spacing: 12) {
                                    Text(food.cartoonIcon).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(food.name).font(.subheadline.weight(.semibold))
                                        Text(food.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(TallyPressStyle()).foregroundStyle(MacroTheme.text)
                        }
                    }.tallyPanel()
                }
                option(.search, title: "Search foods", subtitle: "Search foods stored on your phone", icon: "magnifyingglass", prominent: true)
                option(.barcode, title: "Scan a barcode", subtitle: "Use the nutrition on your package", icon: "barcode.viewfinder", prominent: false)
            }
            .padding(24)
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize || !recentFoods.isEmpty ? [.large] : [.height(350), .large])
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
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var feedback: TallyFeedback
    @Environment(\.calendar) private var calendar
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
                    NavigationLink {
                        NutrientDetailsView(entries: dayEntries)
                    } label: {
                        HStack {
                            Label("Vitamins, minerals & more", systemImage: "leaf")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }.font(.subheadline.weight(.medium)).foregroundStyle(.secondary).padding(.vertical, 12)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if showsOverview {
                    Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text("Daily overview").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                } else {
                    Button { changeDay(by: -7) } label: {
                        Image(systemName: "chevron.left").frame(width: 44, height: 44)
                    }.accessibilityLabel("Previous week")
                    Spacer(minLength: 0)
                    Button { isShowingDatePickerSheet = true } label: {
                        Label(selectedDate.formatted(.dateTime.month(.wide).year()), systemImage: "calendar")
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }.accessibilityLabel("Choose date")
                    Spacer(minLength: 0)
                    Button { changeDay(by: 7) } label: {
                        Image(systemName: "chevron.right").frame(width: 44, height: 44)
                    }.accessibilityLabel("Next week")
                }
            }
            if !showsOverview {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(DiaryDates.week(containing: selectedDate, calendar: calendar), id: \.self) { day in
                            Button { selectedDate = day } label: {
                                VStack(spacing: 8) {
                                    Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption)
                                    Text(day.formatted(.dateTime.day())).font(.headline)
                                }
                                .frame(minWidth: 40, minHeight: 64).padding(.horizontal, 2)
                                .foregroundStyle(calendar.isDate(day, inSameDayAs: selectedDate) ? .white : MacroTheme.text)
                                .background(calendar.isDate(day, inSameDayAs: selectedDate) ? MacroTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 16))
                            }
                            .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                            .accessibilityAddTraits(calendar.isDate(day, inSameDayAs: selectedDate) ? [.isSelected] : [])
                        }
                    }.frame(minWidth: 0, maxWidth: .infinity)
                }
                HStack {
                    Text(formattedSelectedDate).font(.headline)
                    Spacer()
                    if !isSelectedDateToday {
                        Button("Today") { selectedDate = Date() }.frame(minHeight: 44)
                    }
                }
            }
        }.buttonStyle(TallyPressStyle())
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
        .background(MacroTheme.surface.opacity(contrast == .increased ? 1 : 0.55), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(contrast == .increased ? MacroTheme.text.opacity(0.5) : .clear, lineWidth: 1)
        }
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
                    if showsOverview {
                        ForEach(dayEntries) { entry in entryRow(entry) }
                    } else {
                        ForEach(DiaryPeriod.allCases) { period in
                            let entries = dayEntries.filter { DiaryPeriod.period(for: $0.date, calendar: calendar) == period }
                            if !entries.isEmpty {
                                HStack {
                                    Text(period.rawValue).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("\(MacroTheme.formatCalories(DiaryTotals(entries: entries).calories)) kcal")
                                        .font(.caption).foregroundStyle(.secondary)
                                }.padding(.top, 12).accessibilityAddTraits(.isHeader)
                                ForEach(entries) { entry in entryRow(entry) }
                            }
                        }
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
                    if !showsOverview {
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                Text(entry.displayName).font(.headline)
                                Spacer()
                                Text("\(MacroTheme.formatCalories(entry.calories)) kcal").font(.subheadline.weight(.semibold))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.displayName).font(.headline)
                                Text("\(MacroTheme.formatCalories(entry.calories)) kcal").font(.subheadline.weight(.semibold))
                            }
                        }
                        Text([entry.portionDescription, entry.date.formatted(date: .omitted, time: .shortened)].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    } else if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(FoodEmoji.forName(entry.displayName)).accessibilityHidden(true)
                                Text(entry.displayName).font(.headline)
                            }
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
                            HStack(spacing: 8) {
                                Text(FoodEmoji.forName(entry.displayName)).accessibilityHidden(true)
                                Text(entry.displayName).font(.headline)
                            }
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
                    deleteEntry(entry)
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
                deleteEntry(entry)
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
    
    private func deleteEntry(_ entry: MacroEntry) {
        do { try feedback.delete(entry, in: modelContext) }
        catch { saveError = error.localizedDescription }
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

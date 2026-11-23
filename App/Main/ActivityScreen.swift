import SwiftUI
import CritiqueCore

struct ActivityScreen: View {
    var body: some View {
        List {
            NavigationLink { WorkoutsScreen() } label: { Label("Workouts and routines", systemImage: "figure.strengthtraining.traditional") }
            NavigationLink { NutritionScreen() } label: { Label("Nutrition and water", systemImage: "fork.knife") }
            NavigationLink { FocusScreen() } label: { Label("Focus and timers", systemImage: "timer") }
            NavigationLink { CalendarScreen() } label: { Label("Activity calendar", systemImage: "calendar") }
            NavigationLink { ManualScreenTimeScreen() } label: { Label("Screen-time journal", systemImage: "iphone") }
        }.navigationTitle("Activity")
    }
}

private struct ManualScreenTimeScreen: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var entry: ScreenTimeEntry?
    var body: some View {
        List {
            Section { Text("These entries are manual. This build does not collect device screen-time data automatically. Native collection requires a separately configured and approved device-permission integration.").font(.caption) }
            Button("Add manual entry") { entry = ScreenTimeEntry() }
            if let state = store.state {
                ForEach(state.screenTime.sorted { $0.date > $1.date }) { value in
                    Button { entry = value } label: {
                        VStack(alignment: .leading) {
                            Text("\(value.minutes) min · Manual")
                            Text(value.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            if !value.note.isEmpty { Text(value.note).font(.caption) }
                        }
                    }.tint(.primary)
                }
            }
        }.navigationTitle("Screen-time journal").sheet(item: $entry) { ScreenTimeEditor(entry: $0) }
    }
}
private struct ScreenTimeEditor: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @State var entry: ScreenTimeEntry
    @State private var deleting = false
    var body: some View {
        EditorNavigationStack {
            Form {
                Text("Source: Manual").foregroundStyle(.secondary)
                DatePicker("Date", selection: $entry.date, in: ...Date())
                LabeledContent("Minutes") { TextField("Minutes", value: $entry.minutes, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                TextField("Note", text: $entry.note, axis: .vertical)
                if store.state?.screenTime.contains(where: { $0.id == entry.id }) == true { Button("Delete entry", role: .destructive) { deleting = true } }
            }.navigationTitle("Manual screen time").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    if store.change({ state in
                        if let i = state.screenTime.firstIndex(where: { $0.id == entry.id }) { state.screenTime[i] = entry } else { state.screenTime.append(entry) }
                    }) { dismiss() }
                } }
            }.confirmationDialog("Delete this manual entry?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete entry", role: .destructive) { if store.change({ $0.screenTime.removeAll { $0.id == entry.id } }) { dismiss() } }
            }
        }
    }
}

struct NutritionScreen: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var day = Date()
    @State private var meal: Meal?
    @State private var food: Food?
    @State private var water: Water?
    var body: some View {
        List {
            DatePicker("Day", selection: $day, in: ...Date(), displayedComponents: .date)
            if let state = store.state {
                let stats = state.stats(on: day)
                Section("Recorded totals") {
                    LabeledContent("Calories", value: stats.calories.formatted())
                    LabeledContent("Protein", value: "\(stats.protein.formatted()) g")
                    LabeledContent("Carbohydrates", value: "\(stats.carbs.formatted()) g")
                    LabeledContent("Fat", value: "\(stats.fat.formatted()) g")
                    LabeledContent("Water", value: "\(stats.water) mL")
                    Text("Totals reflect saved entries, not an estimate of everything consumed.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Meals") {
                    Button("Record meal") { var entry = Meal(); entry.date = day; meal = entry }
                    ForEach(state.meals.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }.sorted { $0.date < $1.date }) { entry in
                        Button { meal = entry } label: {
                            VStack(alignment: .leading) {
                                Text(entry.food.name)
                                Text("\(entry.category) · \(entry.servings.formatted()) servings · \((entry.food.calories * entry.servings).formatted()) kcal").font(.caption).foregroundStyle(.secondary)
                            }
                        }.tint(.primary)
                    }
                }
                Section("Water entries") {
                    Button("Add water") { var entry = Water(); entry.date = day; water = entry }
                    ForEach(state.water.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }) { entry in
                        Button("\(entry.milliliters) mL · \(entry.date.formatted(date: .omitted, time: .shortened))") { water = entry }
                    }
                }
                Section("Custom food library") {
                    Button("Create food") { food = Food() }
                    ForEach(state.foods) { entry in
                        Button { food = entry } label: { LabeledContent(entry.name, value: "\(entry.calories.formatted()) kcal / serving") }.tint(.primary)
                    }
                }
            }
        }.navigationTitle("Nutrition")
            .sheet(item: $meal) { MealEditor(meal: $0) }
            .sheet(item: $food) { FoodEditor(food: $0) }
            .sheet(item: $water) { WaterEditor(water: $0) }
    }
}

private struct FoodFields: View {
    @Binding var food: Food
    var body: some View {
        TextField("Food name", text: $food.name)
        TextField("Food category", text: $food.category)
        number("Calories per serving", value: $food.calories)
        number("Protein (g)", value: $food.protein)
        number("Carbohydrates (g)", value: $food.carbs)
        number("Fat (g)", value: $food.fat)
    }
    private func number(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent(title) { TextField(title, value: value, format: .number).multilineTextAlignment(.trailing).keyboardType(.decimalPad) }
    }
}
private struct FoodEditor: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @State var food: Food
    @State private var deleting = false
    var body: some View {
        EditorNavigationStack {
            Form {
                Section("Per serving · all values editable") { FoodFields(food: $food) }
                Section { Text("Editing a library food does not change meals already saved. Edit the meal itself to correct its nutrition.").font(.caption) }
                if store.state?.foods.contains(where: { $0.id == food.id }) == true { Button("Delete library food", role: .destructive) { deleting = true } }
            }.navigationTitle("Custom food").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    if store.change({ state in
                        if let i = state.foods.firstIndex(where: { $0.id == food.id }) { state.foods[i] = food } else { state.foods.append(food) }
                    }) { dismiss() }
                } }
            }.confirmationDialog("Delete this library food? Saved meals will remain.", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete food", role: .destructive) { if store.change({ $0.foods.removeAll { $0.id == food.id } }) { dismiss() } }
            }
        }
    }
}
private struct MealEditor: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @State var meal: Meal
    @State private var deleting = false
    var body: some View {
        EditorNavigationStack {
            Form {
                DatePicker("Time", selection: $meal.date, in: ...Date())
                Picker("Meal", selection: $meal.category) { ForEach(["Breakfast", "Lunch", "Dinner", "Snack"], id: \.self) { Text($0) } }
                if let foods = store.state?.foods, !foods.isEmpty {
                    Menu("Use a saved food") { ForEach(foods) { entry in Button(entry.name) { meal.food = entry } } }
                }
                Section("Nutrition per serving") { FoodFields(food: $meal.food) }
                LabeledContent("Servings") { TextField("Servings", value: $meal.servings, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                if store.state?.meals.contains(where: { $0.id == meal.id }) == true { Button("Delete meal", role: .destructive) { deleting = true } }
            }.navigationTitle("Meal").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    if store.change({ state in
                        if let i = state.meals.firstIndex(where: { $0.id == meal.id }) { state.meals[i] = meal } else { state.meals.append(meal) }
                    }) { dismiss() }
                } }
            }.confirmationDialog("Delete this meal?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete meal", role: .destructive) { if store.change({ $0.meals.removeAll { $0.id == meal.id } }) { dismiss() } }
            }
        }
    }
}
private struct WaterEditor: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @State var water: Water
    @State private var deleting = false
    var body: some View {
        EditorNavigationStack {
            Form {
                DatePicker("Time", selection: $water.date, in: ...Date())
                LabeledContent("Milliliters") { TextField("mL", value: $water.milliliters, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                if store.state?.water.contains(where: { $0.id == water.id }) == true { Button("Delete water entry", role: .destructive) { deleting = true } }
            }.navigationTitle("Water").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    if store.change({ state in
                        if let i = state.water.firstIndex(where: { $0.id == water.id }) { state.water[i] = water } else { state.water.append(water) }
                    }) { dismiss() }
                } }
            }.confirmationDialog("Delete this water entry?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete entry", role: .destructive) { if store.change({ $0.water.removeAll { $0.id == water.id } }) { dismiss() } }
            }
        }
    }
}

struct FocusScreen: View {
    var initialMinutes = 25.0
    var initialKind = "Work"
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var minutes = 25.0
    @State private var kind = "Work"
    var body: some View {
        List {
            if let state = store.state {
                if let timer = state.timer {
                    Section("\(timer.kind) timer") {
                        Text(timer.deadline, style: .timer).font(.system(.largeTitle, design: .monospaced))
                        Text("Ends \(timer.deadline.formatted(date: .omitted, time: .shortened))")
                        Button("Cancel without saving", role: .destructive) { store.change { $0.settleTimer(cancel: true) } }
                    }
                } else {
                    Section("New session") {
                        Picker("Type", selection: $kind) { Text("Work").tag("Work"); Text("Break").tag("Break"); Text("Rest").tag("Rest") }
                        LabeledContent("Minutes") { TextField("Minutes", value: $minutes, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                        Button("Start timer") { store.change { $0.timer = RunningTimer(minutes: minutes, kind: kind) } }.disabled(minutes <= 0 || minutes > 1440)
                    }
                }
                Section { Text("The deadline is saved across app restarts. Completed sessions are recorded once. Enable Focus notifications in Settings for an alert when the timer ends.").font(.caption) }
                Section("Session history") {
                    if state.focus.isEmpty { Text("No completed sessions yet.").foregroundStyle(.secondary) }
                    ForEach(state.focus.sorted { $0.started > $1.started }) { entry in
                        LabeledContent("\(entry.kind) · \(entry.started.formatted(date: .abbreviated, time: .shortened))", value: "\(Int(entry.seconds) / 60)m \(Int(entry.seconds) % 60)s")
                    }
                }
            }
        }.navigationTitle("Focus")
            .onAppear { minutes = initialMinutes; kind = initialKind; settleIfNeeded() }
            .onChange(of: scenePhase) { _, value in if value == .active { settleIfNeeded() } }
            .task {
                while !Task.isCancelled {
                    settleIfNeeded()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
    }
    private func settleIfNeeded() {
        if let timer = store.state?.timer, timer.deadline <= Date() { store.change { $0.settleTimer() } }
    }
}

struct CalendarScreen: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var day = Date()
    var body: some View {
        List {
            DatePicker("Activity date", selection: $day, in: ...Date(), displayedComponents: .date).datePickerStyle(.graphical)
            if let state = store.state {
                Section("Completed habits") {
                    let completed = state.habits.filter { $0.completed.contains(Day.key(day)) }
                    if completed.isEmpty { Text("No habit completions recorded.").foregroundStyle(.secondary) }
                    ForEach(completed) { Text($0.title) }
                }
                Section("Workouts") {
                    let workouts = state.workouts.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
                    if workouts.isEmpty { Text("No workouts recorded.").foregroundStyle(.secondary) }
                    ForEach(workouts) { Text("\($0.title) · \(Int($0.minutes)) min") }
                }
                Section("Completed goals") {
                    let goals = state.goals.filter { $0.completedDate.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false }
                    if goals.isEmpty { Text("No goal completions recorded.").foregroundStyle(.secondary) }
                    ForEach(goals) { Text($0.title) }
                }
                Section("Focus") {
                    let stats = state.stats(on: day)
                    Text("\(Int(stats.focusMinutes)) work-focus minutes recorded")
                }
            }
        }.navigationTitle("Calendar")
    }
}

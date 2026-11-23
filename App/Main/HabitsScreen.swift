import SwiftUI
import CritiqueCore

struct HabitsScreen: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var date = Date()
    @State private var editing: Habit?
    @State private var deleting: Habit?
    var body: some View {
        List {
            DatePicker("Review date", selection: $date, in: ...Date(), displayedComponents: .date)
            if let state = store.state {
                if state.habits.isEmpty {
                    ContentUnavailableView("Create your first habit", systemImage: "checkmark.circle",
                        description: Text("Choose an action and the days it belongs in your routine."))
                }
                ForEach(state.habits) { habit in
                    let scheduled = habit.scheduled(on: date)
                    HStack(spacing: 12) {
                        Button {
                            store.change { try $0.toggleHabit(habit.id, on: date) }
                        } label: {
                            Image(systemName: habit.completed.contains(Day.key(date)) ? "checkmark.circle.fill" : "circle")
                                .font(.title2).frame(width: 36, height: 44)
                        }.buttonStyle(.plain).disabled(!scheduled)
                            .accessibilityLabel("\(habit.title), \(habit.completed.contains(Day.key(date)) ? "completed" : "not completed")")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(habit.title).font(.headline)
                            Text(scheduled ? "\(habit.category) · \(habit.streak(at: date)) scheduled-day streak" : "Not scheduled for this date")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { editing = habit } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
                            .accessibilityLabel("Edit \(habit.title)")
                    }
                    .swipeActions { Button("Delete", role: .destructive) { deleting = habit } }
                }
            }
        }.navigationTitle("Habits")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { editing = Habit() } label: { Image(systemName: "plus") }.accessibilityLabel("Create habit") } }
            .sheet(item: $editing) { HabitEditor(habit: $0) }
            .confirmationDialog("Delete \(deleting?.title ?? "habit") and its completion history?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete habit", role: .destructive) {
                    if let id = deleting?.id { store.change { $0.habits.removeAll { $0.id == id } } }
                    deleting = nil
                }
            }
    }
}
private struct HabitEditor: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @State var habit: Habit
    var body: some View {
        EditorNavigationStack {
            Form {
                TextField("Habit name", text: $habit.title)
                TextField("Category", text: $habit.category)
                Section { ReminderTimeField(minute: $habit.reminderMinute) }
                Section("Scheduled days") {
                    ForEach(1...7, id: \.self) { day in
                        Toggle(Calendar.current.weekdaySymbols[day - 1], isOn: Binding(get: { habit.weekdays.contains(day) }, set: { value in
                            if value { habit.weekdays.insert(day) } else { habit.weekdays.remove(day) }
                        }))
                    }
                }
            }.navigationTitle("Habit").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { if store.save(habit) { dismiss() } } }
            }
        }
    }
}

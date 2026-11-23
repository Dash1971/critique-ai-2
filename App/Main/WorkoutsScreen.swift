import SwiftUI
import CritiqueCore
import Charts

struct WorkoutsScreen: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var workout: Workout?
    @State private var routine: Routine?
    var body: some View {
        List {
            if let state = store.state {
                Section("Training") {
                    Button("Record workout") { workout = Workout() }
                    NavigationLink("Rest timer") { FocusScreen(initialMinutes: 1, initialKind: "Rest") }
                }
                Section("Custom routines") {
                    Button("Create routine") { routine = Routine() }
                    ForEach(state.routines) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.title).font(.headline)
                            Text("\(entry.exercises.count) exercises · \(schedule(entry.weekdays))").font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("Record session") { var draft = Workout(title: entry.title); draft.exercises = entry.exercises; workout = draft }
                                Spacer(); Button("Edit") { routine = entry }
                            }.buttonStyle(.borderless)
                        }
                    }
                }
                Section("Last seven days · recorded minutes") {
                    Chart(state.series(days: 7)) { day in
                        let minutes = state.workouts.filter { Day.key($0.date) == day.day }.reduce(0) { $0 + $1.minutes }
                        BarMark(x: .value("Day", day.day), y: .value("Minutes", minutes))
                    }.frame(height: 130).chartXAxis(.hidden)
                }
                Section("Workout history") {
                    if state.workouts.isEmpty { Text("No workouts recorded yet.").foregroundStyle(.secondary) }
                    ForEach(state.workouts.sorted { $0.date > $1.date }) { entry in
                        Button { workout = entry } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.title).font(.headline)
                                Text("\(entry.date.formatted(date: .abbreviated, time: .shortened)) · \(Int(entry.minutes)) min · \(entry.exercises.count) exercises").font(.caption).foregroundStyle(.secondary)
                            }
                        }.tint(.primary)
                    }
                }
                Section("Recorded personal bests · kg") {
                    let names = Set(state.workouts.flatMap(\.exercises).filter { $0.weight > 0 }.map(\.name)).sorted()
                    if names.isEmpty { Text("Add weighted exercise entries to see recorded bests.").foregroundStyle(.secondary) }
                    ForEach(names, id: \.self) { name in LabeledContent(name, value: "\(state.personalRecord(for: name).formatted()) kg") }
                }
            }
        }.navigationTitle("Workouts")
            .sheet(item: $workout) { WorkoutEditor(workout: $0) }
            .sheet(item: $routine) { RoutineEditor(routine: $0) }
    }
    private func schedule(_ weekdays: Set<Int>) -> String {
        weekdays.sorted().map { Calendar.current.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
    }
}

private struct ExerciseFields: View {
    @Binding var exercise: Exercise
    var body: some View {
        TextField("Exercise name", text: $exercise.name)
        Picker("Category", selection: $exercise.kind) {
            ForEach(["Calisthenics", "Weight training", "Cardio", "Flexibility", "General fitness"], id: \.self) { Text($0) }
        }
        TextField("Muscle group", text: $exercise.muscle)
        Stepper("Sets: \(exercise.sets)", value: $exercise.sets, in: 1...10000)
        Stepper("Repetitions: \(exercise.reps)", value: $exercise.reps, in: 1...100000)
        LabeledContent("Weight per set (kg)") { TextField("kg", value: $exercise.weight, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
        LabeledContent("Exercise duration (min)") { TextField("Minutes", value: $exercise.minutes, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
    }
}
private struct WorkoutEditor: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @State var workout: Workout
    @State private var deleting = false
    var body: some View {
        EditorNavigationStack {
            Form {
                Section("Session") {
                    TextField("Workout title", text: $workout.title)
                    DatePicker("Date", selection: $workout.date, in: ...Date())
                    LabeledContent("Total duration (min)") { TextField("Minutes", value: $workout.minutes, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    TextField("Notes", text: $workout.notes, axis: .vertical).lineLimit(2...5)
                }
                ForEach($workout.exercises) { $exercise in
                    Section {
                        ExerciseFields(exercise: $exercise)
                        Button("Remove exercise", role: .destructive) { workout.exercises.removeAll { $0.id == exercise.id } }
                    }
                }
                Button("Add exercise") { workout.exercises.append(Exercise()) }
                Section { Text("Each entry uses the same weight and repetitions for its set count. For differing sets, add separate entries with the same exercise name and one set each. Weights are kilograms.").font(.caption) }
                if store.state?.workouts.contains(where: { $0.id == workout.id }) == true { Button("Delete workout", role: .destructive) { deleting = true } }
            }.navigationTitle("Workout").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    if store.change({ state in
                        if let i = state.workouts.firstIndex(where: { $0.id == workout.id }) { state.workouts[i] = workout } else { state.workouts.append(workout) }
                    }) { dismiss() }
                } }
            }.confirmationDialog("Delete this workout?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete workout", role: .destructive) { if store.change({ $0.workouts.removeAll { $0.id == workout.id } }) { dismiss() } }
            }
        }
    }
}
private struct RoutineEditor: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @State var routine: Routine
    @State private var deleting = false
    var body: some View {
        EditorNavigationStack {
            Form {
                TextField("Routine title", text: $routine.title)
                Section { ReminderTimeField(minute: $routine.reminderMinute) }
                Section("Scheduled days") {
                    ForEach(1...7, id: \.self) { day in
                        Toggle(Calendar.current.weekdaySymbols[day - 1], isOn: Binding(get: { routine.weekdays.contains(day) }, set: { on in
                            if on { routine.weekdays.insert(day) } else { routine.weekdays.remove(day) }
                        }))
                    }
                }
                ForEach($routine.exercises) { $exercise in
                    Section {
                        ExerciseFields(exercise: $exercise)
                        Button("Remove exercise", role: .destructive) { routine.exercises.removeAll { $0.id == exercise.id } }
                    }
                }
                Button("Add exercise") { routine.exercises.append(Exercise()) }
                if store.state?.routines.contains(where: { $0.id == routine.id }) == true { Button("Delete routine", role: .destructive) { deleting = true } }
            }.navigationTitle("Routine").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    if store.change({ state in
                        if let i = state.routines.firstIndex(where: { $0.id == routine.id }) { state.routines[i] = routine } else { state.routines.append(routine) }
                    }) { dismiss() }
                } }
            }.confirmationDialog("Delete this routine? Saved workouts will remain.", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete routine", role: .destructive) { if store.change({ $0.routines.removeAll { $0.id == routine.id } }) { dismiss() } }
            }
        }
    }
}

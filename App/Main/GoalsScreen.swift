import SwiftUI
import CritiqueCore

struct GoalsScreen: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var editing: Goal?
    @State private var progressing: Goal?
    @State private var deleting: Goal?
    var body: some View {
        List {
            if let state = store.state {
                if state.goals.isEmpty {
                    ContentUnavailableView("Set a useful goal", systemImage: "target",
                        description: Text("Define the outcome, target and deadline. Progress updates are saved in its history."))
                }
                ForEach(state.goals) { goal in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(goal.title).font(.headline); Spacer(); if goal.completed { Image(systemName: "checkmark.seal.fill").accessibilityLabel("Completed") } }
                        if !goal.detail.isEmpty { Text(goal.detail).font(.subheadline) }
                        ProgressView(value: goal.fraction)
                        Text("\(goal.progress.formatted()) / \(goal.target.formatted()) · \(goal.cadence)").font(.caption).monospacedDigit()
                        Text("Deadline: \(goal.deadline.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Update progress") { progressing = goal }
                            Spacer(); Button("Edit") { editing = goal }
                        }.buttonStyle(.borderless)
                    }.padding(.vertical, 6)
                        .swipeActions { Button("Delete", role: .destructive) { deleting = goal } }
                }
            }
        }.navigationTitle("Goals")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { editing = Goal() } label: { Image(systemName: "plus") }.accessibilityLabel("Create goal") } }
            .sheet(item: $editing) { GoalEditor(goal: $0) }
            .sheet(item: $progressing) { GoalProgressEditor(goal: $0) }
            .confirmationDialog("Delete \(deleting?.title ?? "goal") and its history?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete goal", role: .destructive) {
                    if let id = deleting?.id { store.change { $0.goals.removeAll { $0.id == id } } }; deleting = nil
                }
            }
    }
}
private struct GoalEditor: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @State var goal: Goal
    var body: some View {
        EditorNavigationStack {
            Form {
                TextField("Goal title", text: $goal.title)
                TextField("Description", text: $goal.detail, axis: .vertical).lineLimit(2...5)
                TextField("Category", text: $goal.category)
                Picker("Period", selection: $goal.cadence) {
                    ForEach(["Daily", "Weekly", "Monthly", "Yearly"], id: \.self) { Text($0) }
                }
                LabeledContent("Target") { TextField("Target", value: $goal.target, format: .number).multilineTextAlignment(.trailing).keyboardType(.decimalPad) }
                DatePicker("Deadline", selection: $goal.deadline, displayedComponents: .date)
            }.navigationTitle("Goal").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { if store.save(goal) { dismiss() } } }
            }
        }
    }
}
private struct GoalProgressEditor: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    let goal: Goal
    @State private var value = 0.0
    @State private var date = Date()
    var body: some View {
        EditorNavigationStack {
            Form {
                LabeledContent("Total progress") { TextField("Total", value: $value, format: .number).multilineTextAlignment(.trailing).keyboardType(.decimalPad) }
                DatePicker("Recorded date", selection: $date, in: ...Date())
                Section("Saved history") {
                    if goal.updates.isEmpty { Text("No updates recorded.").foregroundStyle(.secondary) }
                    ForEach(goal.updates.sorted { $0.date > $1.date }) { update in
                        LabeledContent(update.date.formatted(date: .abbreviated, time: .shortened), value: update.value.formatted())
                    }
                }
            }.navigationTitle(goal.title).onAppear { value = goal.progress }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        if store.change({ state in
                            guard let index = state.goals.firstIndex(where: { $0.id == goal.id }) else { throw DataError.invalid("This goal no longer exists.") }
                            var update = GoalUpdate(value: value); update.date = date
                            state.goals[index].updates.append(update)
                            state.goals[index].updates.sort { $0.date < $1.date }
                        }) { dismiss() }
                    } }
                }
        }
    }
}

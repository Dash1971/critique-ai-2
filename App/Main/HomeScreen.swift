import SwiftUI
import Charts
import CritiqueCore

@MainActor private final class HomeRoutineModel: ObservableObject {
    @Published var running = false
    @Published var status: String?
    private let worker = ModelWorker()
    private var cancelled = false

    func generate(state: AppState, save: @escaping (DailyRoutinePlan) -> Bool) {
        guard !running else { return }
        let now = Date()
        let context: CoachFactContext
        do { context = try state.coachFactContext(days: 1, now: now) }
        catch { status = error.localizedDescription; return }
        running = true; cancelled = false; status = "Building your routine on this device…"
        worker.run(question: "Propose up to three small activities for today based on the selected habits and goals. Use planning or practice suggestions. Do not claim they are scheduled or completed. Do not invent personal facts.", context: context) { result in
            Task { @MainActor in
                self.running = false
                defer { self.worker.unload() }
                guard !self.cancelled, Calendar.current.isDateInToday(now) else {
                    self.status = "Generation cancelled. No habits were changed."; return
                }
                switch result {
                case .success(let reply):
                    let activities = reply.suggestions.filter { $0.kind == .practice || $0.kind == .planning }
                    guard !activities.isEmpty else {
                        self.status = "No usable routine was generated. Try again or plan your habits manually."; return
                    }
                    let plan = DailyRoutinePlan(suggestions: activities.map {
                        DailyRoutineSuggestion(title: $0.text, proposedMinutes: $0.proposedMinutes)
                    }, now: now)
                    self.status = save(plan) ? "Routine ready. Review a suggestion to schedule it." : "The routine could not be saved. Your habits are unchanged."
                case .failure(let error): self.status = error.localizedDescription
                }
            }
        }
    }
    func cancel() {
        guard running else { return }
        cancelled = true; worker.cancel(); status = "Cancelling…"
    }
}

struct HomeScreen: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var textSize
    @StateObject private var routine = HomeRoutineModel()
    @State private var scheduling: DailyRoutineSuggestion?
    @State private var regenerate = false
    private let cardColor = Color(white: 0.065)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { clock in
            ScrollView {
                if let state = store.state {
                    content(state, now: clock.date)
                }
            }
            .background(Color.black)
            .onChange(of: Day.key(clock.date)) { _, _ in routine.cancel() }
            .onChange(of: clock.date) { _, now in
                if let deadline = store.state?.timer?.deadline, deadline <= now { store.resume() }
            }
        }
        .navigationTitle("Home").navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark).tint(.white)
        .toolbarBackground(Color.black, for: .navigationBar)
        .sheet(item: $scheduling) { RoutineScheduleSheet(suggestion: $0) }
        .confirmationDialog("Replace today's generated suggestions?", isPresented: $regenerate, titleVisibility: .visible) {
            Button("Generate new suggestions") { generate() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Scheduled habits and their completion history will stay unchanged.") }
        .onChange(of: store.state) { old, new in
            guard let old, let new else { routine.cancel(); return }
            if old.habits != new.habits || old.goals != new.goals || old.workouts != new.workouts || old.focus != new.focus || old.meals != new.meals || old.water != new.water {
                routine.cancel()
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { routine.cancel() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in routine.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in routine.cancel() }
        .onDisappear { routine.cancel() }
    }

    private func content(_ state: AppState, now: Date) -> some View {
        let stats = state.stats(on: now)
        return VStack(alignment: .leading, spacing: 24) {
            greeting(state, now: now)
            progress(stats)
            dailyRoutine(state, now: now)
            upcoming(state, now: now)
            if let timer = state.timer {
                NavigationLink { FocusScreen() } label: {
                    card {
                        HStack {
                            Label(timer.kind + " timer", systemImage: "timer").font(.headline)
                            Spacer()
                            Text(timer.deadline, style: .timer).monospacedDigit().font(.headline)
                        }
                        Text("Session time is logged when the timer finishes.").font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                }.buttonStyle(.plain)
            }
            totals(state, stats: stats)
            week(state, now: now)
            experience(state)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 32)
        .frame(maxWidth: 760).frame(maxWidth: .infinity)
        .foregroundStyle(.white)
    }

    private func greeting(_ state: AppState, now: Date) -> some View {
        let hour = Calendar.current.component(.hour, from: now)
        let salutation = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        let name = state.profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 6) {
            Text(now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.subheadline).foregroundStyle(.white.opacity(0.6))
            Text(name == "You" || name.isEmpty ? salutation + "." : salutation + ", " + name + ".")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("home-greeting")
            Text("Make room for what matters today.").font(.subheadline).foregroundStyle(.white.opacity(0.65))
        }
    }

    private func progress(_ stats: DailyStats) -> some View {
        card {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily progress").font(.headline)
                    Text(stats.dueHabits == 0 ? "No habits scheduled today" : "\(stats.doneHabits) of \(stats.dueHabits) scheduled habits completed")
                        .font(.caption).foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 8)
                Text(stats.completion, format: .percent.precision(.fractionLength(0)))
                    .font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
                    .accessibilityIdentifier("home-daily-progress")
            }
            ProgressView(value: stats.completion).tint(.white)
                .accessibilityLabel("Scheduled habit completion")
                .accessibilityValue("\(stats.doneHabits) of \(stats.dueHabits)")
        }
    }

    private func dailyRoutine(_ state: AppState, now: Date) -> some View {
        let habits = state.habits.filter { $0.scheduled(on: now) }.sorted {
            ($0.reminderMinute ?? 1440, $0.title) < ($1.reminderMinute ?? 1440, $1.title)
        }
        let plan = state.dailyRoutine.flatMap { $0.isCurrent(at: now) ? $0 : nil }
        return card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles").font(.title2).padding(12)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your daily routine").font(.title2.bold())
                    Text("AI ideas. Your schedule.").font(.subheadline).foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
            }
            if let plan {
                Text("SUGGESTED FOR TODAY").font(.caption2.weight(.semibold)).tracking(1.3).foregroundStyle(.white.opacity(0.55))
                ForEach(plan.suggestions) { suggestion in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(suggestion.title).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                        if let minutes = suggestion.proposedMinutes {
                            Label("\(minutes) min suggested", systemImage: "clock").font(.caption).foregroundStyle(.white.opacity(0.6))
                        }
                        if let id = suggestion.scheduledHabitID {
                            Label(state.habits.contains(where: { $0.id == id }) ? "Added to your habits" : "Previously scheduled · habit removed", systemImage: "checkmark")
                                .font(.caption).foregroundStyle(.white.opacity(0.65))
                        } else {
                            Button { scheduling = suggestion } label: {
                                Label("Review & schedule", systemImage: "plus.circle").font(.subheadline.weight(.semibold))
                            }.buttonStyle(.bordered).disabled(routine.running)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                }
                Text("Suggestions use saved records at generation time. Refresh for new ideas after changes.")
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
            } else {
                Text("Build a manageable plan from your saved habits and goals, right on this device.")
                    .font(.body).foregroundStyle(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                if state.habits.isEmpty && state.goals.isEmpty {
                    NavigationLink { HabitsScreen() } label: { Label("Add a habit to get started", systemImage: "plus") }
                        .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                    Text("Add a habit or goal first so the routine has something personal to work with.").font(.caption).foregroundStyle(.white.opacity(0.6))
                }
            }
            if !state.habits.isEmpty || !state.goals.isEmpty {
                if routine.running {
                    HStack { ProgressView().tint(.white); Text("Creating your routine…").font(.subheadline); Spacer(); Button("Cancel", action: routine.cancel) }
                } else {
                    Button {
                        if plan == nil { generate() } else { regenerate = true }
                    } label: {
                        HStack { Image(systemName: "sparkles"); Text(plan == nil ? "Generate my routine" : "Refresh suggestions"); Spacer(); Image(systemName: "arrow.right") }
                            .font(.subheadline.weight(.semibold)).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                        .accessibilityIdentifier("home-generate-routine")
                }
            }
            if let status = routine.status { Text(status).font(.caption).foregroundStyle(.white.opacity(0.7)).accessibilityIdentifier("home-routine-status") }
            Text("Experimental AI · review suggestions before using them.").font(.caption2).foregroundStyle(.white.opacity(0.5))
            Divider().overlay(.white.opacity(0.08))
            HStack {
                Text("ON YOUR SCHEDULE").font(.caption2.weight(.semibold)).tracking(1.3).foregroundStyle(.white.opacity(0.55))
                Spacer()
                NavigationLink("Manage") { HabitsScreen() }.font(.caption.weight(.medium))
            }
            if habits.isEmpty { Text("Nothing scheduled today. Keep space for a fresh start.").font(.subheadline).foregroundStyle(.white.opacity(0.65)) }
            ForEach(habits) { habit in
                habitRow(habit, now: now)
            }
        }
    }

    private func habitRow(_ habit: Habit, now: Date) -> some View {
        let done = habit.completed.contains(Day.key(now))
        return HStack(spacing: 12) {
            Button {
                store.change { try $0.toggleHabit(habit.id, on: Date()) }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(done ? .white : .white.opacity(0.45))
                    .frame(width: 44, height: 44)
            }.buttonStyle(.plain)
                .accessibilityLabel("\(habit.title), \(done ? "completed" : "not completed")")
                .accessibilityHint("Toggles this habit's saved completion for today")
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.title).font(.subheadline.weight(.medium)).strikethrough(done).foregroundStyle(done ? .white.opacity(0.5) : .white)
                HStack(spacing: 6) {
                    Text(habit.reminderMinute.map(timeLabel) ?? "Anytime")
                    if habit.aiGenerated == true { Text("· AI suggested") }
                }.font(.caption).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }.accessibilityElement(children: .contain)
    }

    private func upcoming(_ state: AppState, now: Date) -> some View {
        let activities = Array(state.upcomingHomeActivities(now: now).prefix(4))
        return VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Coming up").font(.title3.bold()); Spacer(); NavigationLink("Calendar") { CalendarScreen() }.font(.subheadline) }
            card {
                if activities.isEmpty {
                    Label("No upcoming times or goal deadlines", systemImage: "calendar")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                    Text("Habits without a time appear in your daily routine.").font(.caption).foregroundStyle(.white.opacity(0.5))
                }
                ForEach(activities) { activity in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: activity.kind == .habit ? "checkmark.circle" : activity.kind == .workout ? "dumbbell" : "target")
                            .frame(width: 24).foregroundStyle(.white.opacity(0.65))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(activity.title).font(.subheadline.weight(.medium))
                            Text(activity.kind == .goal ? "Goal deadline" : activity.kind == .workout ? "Workout routine" : "Habit")
                                .font(.caption).foregroundStyle(.white.opacity(0.5))
                            Text(activity.date, format: .dateTime.weekday(.abbreviated).hour().minute())
                                .font(.caption).foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer(minLength: 0)
                    }.padding(.vertical, 3)
                }
            }
        }
    }

    private func totals(_ state: AppState, stats: DailyStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your day, in numbers").font(.title3.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: textSize.isAccessibilitySize ? 240 : 140), spacing: 12)], spacing: 12) {
                NavigationLink { FocusScreen() } label: { metric("Focus logged", value: "\(Int(stats.focusMinutes)) min", icon: "timer", detail: "Work sessions today") }
                NavigationLink { WorkoutsScreen() } label: { metric("Workouts", value: "\(stats.workouts)", icon: "dumbbell", detail: "Saved today") }
                NavigationLink { GoalsScreen() } label: {
                    metric("Goals complete", value: "\(state.goals.filter(\.completed).count) / \(state.goals.count)", icon: "target", detail: "\(stats.completedGoals) completed today")
                }
            }.buttonStyle(.plain)
        }
    }

    private func metric(_ title: String, value: String, icon: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.white.opacity(0.65))
            Text(value).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
            Text(detail).font(.caption2).foregroundStyle(.white.opacity(0.5))
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(16)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .combine)
    }

    private func week(_ state: AppState, now: Date) -> some View {
        let days = state.series(days: 7, until: now)
        return card {
            HStack { VStack(alignment: .leading, spacing: 4) { Text("Weekly progress").font(.title3.bold()); Text("Scheduled habit completion · last 7 days").font(.caption).foregroundStyle(.white.opacity(0.6)) }; Spacer() }
            Chart(days) { day in
                BarMark(x: .value("Day", day.day), y: .value("Completion", day.completion * 100))
                    .foregroundStyle(day.day == Day.key(now) ? Color.white : Color(white: 0.35)).cornerRadius(5)
                    .accessibilityLabel(Day.date(day.day)?.formatted(date: .abbreviated, time: .omitted) ?? day.day)
                    .accessibilityValue(day.dueHabits == 0 ? "No habits scheduled" : "\(day.doneHabits) of \(day.dueHabits) completed")
            }
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(values: [0, 50, 100]) { value in AxisGridLine().foregroundStyle(.white.opacity(0.08)); AxisValueLabel { if let n = value.as(Int.self) { Text("\(n)%").foregroundStyle(.white.opacity(0.5)) } } } }
            .chartXAxis { AxisMarks { value in AxisValueLabel { if let key = value.as(String.self), let date = Day.date(key) { Text(date, format: .dateTime.weekday(.abbreviated)).font(.caption2).foregroundStyle(.white.opacity(0.6)) } } } }
            .frame(height: 155).accessibilityIdentifier("home-weekly-progress")
            Text("Based on saved completions and current habit schedules.").font(.caption2).foregroundStyle(.white.opacity(0.5))
            NavigationLink("Compare recorded periods") { RecordedPeriodComparisonScreen() }.font(.subheadline)
        }
    }

    private func experience(_ state: AppState) -> some View {
        card {
            HStack(alignment: .firstTextBaseline) {
                Label("Level \(state.level)", systemImage: "star.fill").font(.headline)
                Spacer(); Text("\(state.xp) XP").font(.headline).monospacedDigit()
            }
            ProgressView(value: Double(state.xp % 250), total: 250).tint(.white)
                .accessibilityLabel("Progress to next level").accessibilityValue("\(state.xp % 250) of 250 XP")
            Text("\(250 - state.xp % 250) XP to level \(state.level + 1)").font(.caption).foregroundStyle(.white.opacity(0.6))
            if !state.achievements.isEmpty {
                DisclosureGroup("Achievements · \(state.achievements.count)") {
                    ForEach(state.achievements, id: \.self) { Label($0, systemImage: "rosette").font(.subheadline).padding(.top, 6) }
                }.font(.subheadline)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.07), lineWidth: 1))
    }
    private func timeLabel(_ minute: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
    private func generate() {
        guard let state = store.state else { return }
        routine.generate(state: state) { plan in
            guard let current = store.state, current.habits == state.habits, current.goals == state.goals,
                  current.workouts == state.workouts, current.focus == state.focus,
                  current.meals == state.meals, current.water == state.water else { return false }
            return store.change { $0.dailyRoutine = plan }
        }
    }
}

private struct RoutineScheduleSheet: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    let suggestion: DailyRoutineSuggestion
    @State private var title: String
    @State private var time = Date().addingTimeInterval(1800)
    @State private var weekdays: Set<Int> = [Calendar.current.component(.weekday, from: Date())]
    init(suggestion: DailyRoutineSuggestion) {
        self.suggestion = suggestion
        _title = State(initialValue: String(suggestion.title.prefix(200)))
    }
    var body: some View {
        EditorNavigationStack {
            Form {
                Section("Review the suggestion") {
                    TextField("Habit name", text: $title, axis: .vertical)
                        .accessibilityLabel("Habit name").accessibilityIdentifier("home-routine-habit-name")
                    if let minutes = suggestion.proposedMinutes { Text("Suggested duration: \(minutes) min").font(.caption) }
                    Text("Saving creates a habit. It does not mark anything complete.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Choose a time") {
                    DatePicker("Scheduled time", selection: $time, displayedComponents: .hourAndMinute)
                    Text("Notification delivery depends on your notification settings and permission.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Repeat on selected days") {
                    ForEach(1...7, id: \.self) { day in
                        Toggle(Calendar.current.weekdaySymbols[day - 1], isOn: Binding(get: { weekdays.contains(day) }, set: { value in
                            if value { weekdays.insert(day) } else { weekdays.remove(day) }
                        }))
                    }
                }
            }.navigationTitle("Schedule habit").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add habit") {
                        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
                        if store.change({ try $0.scheduleRoutineSuggestion(suggestion.id, title: title, minute: (components.hour ?? 0) * 60 + (components.minute ?? 0), weekdays: weekdays) }) { dismiss() }
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || weekdays.isEmpty)
                }
            }
        }
    }
}

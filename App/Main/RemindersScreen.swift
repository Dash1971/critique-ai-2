import SwiftUI
import UserNotifications
import CritiqueCore

final class ForegroundReminderPresentation: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ForegroundReminderPresentation()
    static func install() { UNUserNotificationCenter.current().delegate = shared }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

actor ReminderCoordinator {
    static let shared = ReminderCoordinator()
    private let center = UNUserNotificationCenter.current()
    private var pending: AppState?
    private var applying = false
    private(set) var lastProblem: String?
    func refresh(_ state: AppState) async {
        pending = state
        guard !applying else { return }
        applying = true
        defer { applying = false }
        // Conflate updates and serialize complete applications. An old pending
        // add cannot race past a newer cancellation/reminder configuration.
        while let next = pending {
            pending = nil
            await apply(next)
        }
    }
    private func apply(_ state: AppState) async {
        lastProblem = nil
        let old = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: old.filter { $0.identifier.hasPrefix("critique.reminder.") }.map(\.identifier))
        let permission = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(permission.authorizationStatus) else { return }
        for reminder in state.reminderPlan().requests {
            let remaining = reminder.date.timeIntervalSinceNow
            guard remaining > 0 else { continue }
            let content = UNMutableNotificationContent()
            content.title = reminder.title; content.body = reminder.body; content.sound = .default
            let trigger: UNNotificationTrigger
            if reminder.isTimer { trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, remaining), repeats: false) }
            else {
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.date)
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            }
            do { try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)) }
            catch { lastProblem = error.localizedDescription }
        }
    }
}

struct RemindersScreen: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var permission = "Checking…"
    @State private var count = 0
    @State private var problem: String?
    var body: some View {
        Form {
            Section("Device permission") {
                LabeledContent("Status", value: permission)
                Button("Allow notifications") {
                    Task {
                        do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]); await refresh() }
                        catch { problem = error.localizedDescription }
                    }
                }
                Button("Open device notification settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            Section("Reminder types") {
                ForEach(ReminderKind.allCases) { kind in
                    Toggle(kind.rawValue, isOn: Binding(get: { store.state?.settings.notifications.contains(kind.rawValue) ?? false }, set: { enabled in
                        store.change { if enabled { $0.settings.notifications.insert(kind.rawValue) } else { $0.settings.notifications.remove(kind.rawValue) } }
                        Task { await refresh() }
                    }))
                }
                Text("Choose individual habit and routine times in their editors. Goal alerts are at nine in the morning on the deadline and previous day. Focus alerts follow the saved timer.").font(.caption)
            }
            Section("Upcoming queue") {
                LabeledContent("Queued on this device", value: String(count))
                Text("Upcoming reminders are refreshed when the app opens or records change. A rolling batch is queued; device permissions, notification capacity and Focus settings can affect delivery.").font(.caption)
                if let state = store.state, state.reminderPlan().additionalUpcomingCount > 0 {
                    Text("\(state.reminderPlan().additionalUpcomingCount) additional upcoming reminders are outside the current batch. Open the app regularly to refresh the queue.").font(.caption)
                }
                if let problem { Text(problem).foregroundStyle(.red) }
                Button("Refresh reminder queue") { Task { await refresh() } }
            }
        }.navigationTitle("Notifications").task { await refresh() }
    }
    private func refresh() async {
        if let state = store.state { await ReminderCoordinator.shared.refresh(state) }
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized: permission = "Allowed"
        case .provisional: permission = "Quiet delivery"
        case .ephemeral: permission = "Temporary permission"
        case .denied: permission = "Not allowed in device settings"
        case .notDetermined: permission = "Not requested"
        @unknown default: permission = "Unknown"
        }
        count = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("critique.reminder.") }.count
        problem = await ReminderCoordinator.shared.lastProblem
    }
}

struct ReminderTimeField: View {
    @Binding var minute: Int?
    var body: some View {
        Toggle("Reminder time", isOn: Binding(get: { minute != nil }, set: { minute = $0 ? 9 * 60 : nil }))
        if minute != nil {
            DatePicker("Time", selection: Binding(get: {
                let value = minute ?? 9 * 60
                return Calendar.current.date(bySettingHour: value / 60, minute: value % 60, second: 0, of: Date()) ?? Date()
            }, set: { value in minute = Calendar.current.component(.hour, from: value) * 60 + Calendar.current.component(.minute, from: value) }), displayedComponents: .hourAndMinute)
            Text("Enable this reminder type in Settings and allow device notifications to receive alerts.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

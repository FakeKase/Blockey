import SwiftUI

struct SettingsView: View {
    @Environment(CalendarService.self) private var calendars
    @Environment(\.dismiss) private var dismiss

    @AppStorage(SettingsKey.dayStartMinute) private var dayStartMinute = SettingsKey.defaultDayStart
    @AppStorage(SettingsKey.dayEndMinute) private var dayEndMinute = SettingsKey.defaultDayEnd
    @AppStorage(SettingsKey.snapMinutes) private var snapMinutes = SettingsKey.defaultSnap
    @AppStorage(SettingsKey.hiddenCalendarIDs) private var hiddenCalendarsRaw = ""
    @AppStorage(SettingsKey.alarmEnabled) private var alarmEnabled = false
    @AppStorage(SettingsKey.alarmMinutesBefore) private var alarmMinutesBefore = 5

    private var hiddenIDs: Set<String> {
        Set(hiddenCalendarsRaw.split(separator: "\n").map(String.init))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Day starts", selection: binding(for: $dayStartMinute), displayedComponents: .hourAndMinute)
                    DatePicker("Day ends", selection: binding(for: $dayEndMinute), displayedComponents: .hourAndMinute)
                } header: {
                    Text("Planning window")
                } footer: {
                    Text("Blockey only looks for free time inside these hours. Meetings outside them still show, dimmed.")
                }

                Section("Snap") {
                    Picker("Snap to", selection: $snapMinutes) {
                        ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Alert at block start", isOn: $alarmEnabled)
                    if alarmEnabled {
                        Stepper(alarmMinutesBefore == 0 ? "At start time" : "\(alarmMinutesBefore) min before",
                                value: $alarmMinutesBefore, in: 0...60, step: 5)
                    }
                } header: {
                    Text("Alerts")
                } footer: {
                    Text("Alerts are set on the calendar event itself, so they fire through Calendar — no extra notification permission needed.")
                }

                Section {
                    ForEach(calendars.selectableCalendars(), id: \.calendarIdentifier) { calendar in
                        Toggle(isOn: binding(forCalendarID: calendar.calendarIdentifier)) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(cgColor: calendar.cgColor))
                                    .frame(width: 9, height: 9)
                                Text(calendar.title)
                            }
                        }
                    }
                } header: {
                    Text("Plan around these calendars")
                } footer: {
                    Text("Turn one off and its events stop blocking out time.")
                }

                Section {
                    LabeledContent("Blocks are saved to") {
                        Text(calendars.blockeyCalendar()?.title ?? "Not created yet")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Blockey writes every block to this calendar, so your plan is visible on your other devices and survives reinstalling the app.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Minutes-past-midnight stored as an `Int`, edited as a time of day.
    private func binding(for storage: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(storage.wrappedValue * 60))
        } set: { newValue in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            storage.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    /// The toggle reads "plan around this calendar", so it is the inverse of hidden.
    private func binding(forCalendarID id: String) -> Binding<Bool> {
        Binding {
            !hiddenIDs.contains(id)
        } set: { include in
            var ids = hiddenIDs
            if include { ids.remove(id) } else { ids.insert(id) }
            hiddenCalendarsRaw = ids.sorted().joined(separator: "\n")
        }
    }
}

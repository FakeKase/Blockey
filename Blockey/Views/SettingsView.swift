import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(CalendarService.self) private var calendars
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.categoryCatalog) private var catalog
    #if DEBUG && targetEnvironment(simulator)
    @State private var demoPushCategories = false
    #endif

    @State private var exportDocument: BackupFile?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var backupMessage: String?
    @State private var pendingRestore: PendingRestore?

    @AppStorage(SettingsKey.dayStartMinute) private var dayStartMinute = SettingsKey.defaultDayStart
    @AppStorage(SettingsKey.dayEndMinute) private var dayEndMinute = SettingsKey.defaultDayEnd
    @AppStorage(SettingsKey.snapMinutes) private var snapMinutes = SettingsKey.defaultSnap
    @AppStorage(SettingsKey.hiddenCalendarIDs) private var hiddenCalendarsRaw = ""
    @AppStorage(SettingsKey.alarmEnabled) private var alarmEnabled = false
    @AppStorage(SettingsKey.alarmMinutesBefore) private var alarmMinutesBefore = 5
    @AppStorage(SettingsKey.skipPlanPreview) private var skipPlanPreview = false

    @Query private var activityDays: [ActivityDay]

    #if DEBUG
    @State private var tokenProbe = TokenProbe.load()
    @State private var tokenProbeReport: String?
    #endif

    private var hiddenIDs: Set<String> {
        Set(hiddenCalendarsRaw.split(separator: "\n").map(String.init))
    }

    /// Re-read when a day is added (the query changes), so the row is live while Settings is open.
    private var bestStreak: Int {
        _ = activityDays.count
        return StreakStore(context: context, calendar: .current).summary(now: .now).longest
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
                    Toggle("Skip preview", isOn: $skipPlanPreview)
                } footer: {
                    Text("Add your template with one tap, without checking the plan first. You can undo it. Days that already have blocks always show the preview.")
                }

                Section {
                    NavigationLink {
                        CategoriesListView()
                    } label: {
                        LabeledContent("Categories") {
                            Text("\(catalog.activeInOrder().count)").foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Categories, \(catalog.activeInOrder().count)")
                    .accessibilityAddTraits(.isButton)
                } footer: {
                    Text("Names, emoji and colours for your blocks. Changing one updates everything that uses it.")
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
                    Text("Alerts are set on the calendar event itself, so they fire through Calendar and need no extra notification permission.")
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
                    LabeledContent("Streak") {
                        Text(StreakCopy.best(bestStreak))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                } footer: {
                    Text(StreakCopy.settingsFooter)
                }

                Section {
                    LabeledContent("Blocks are saved to") {
                        Text(calendars.blockeyCalendar()?.title ?? "Not created yet")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Blockey writes every block to this calendar, so your plan is visible on your other devices and survives reinstalling the app.")
                }

                Section {
                    Button {
                        exportBackup()
                    } label: {
                        Label("Export tasks & templates", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        isImporting = true
                    } label: {
                        Label("Restore from a backup", systemImage: "square.and.arrow.down")
                    }
                    if let backupMessage {
                        Text(backupMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Your blocks are already safe in Calendar. Tasks and templates live only on this phone. They survive reinstalling Blockey, but not deleting it.")
                }

                #if DEBUG
                if calendars.canRunTokenProbe {
                    tokenProbeSection
                }
                #endif
            }
            #if DEBUG && targetEnvironment(simulator)
            .navigationDestination(isPresented: $demoPushCategories) { CategoriesListView() }
            .task { if DemoScenario.wantsCategories { demoPushCategories = true } }
            #endif
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileExporter(isPresented: $isExporting,
                          document: exportDocument,
                          contentType: .json,
                          defaultFilename: exportDocument?.backup.suggestedFilename) { result in
                switch result {
                case .success: backupMessage = "Backup saved."
                case .failure(let error): backupMessage = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                stageRestore(result)
            }
            // Restoring deletes every task and template before inserting the
            // backup's, so it must never happen on the strength of one tap in a
            // file picker. The counts go in the message because "replace" means
            // nothing without knowing what is being replaced.
            .alert("Replace your tasks and templates?",
                   isPresented: Binding(get: { pendingRestore != nil },
                                        set: { if !$0 { pendingRestore = nil } }),
                   presenting: pendingRestore) { pending in
                Button("Replace", role: .destructive) { restore(pending) }
                Button("Cancel", role: .cancel) {}
            } message: { pending in
                Text(pending.warning)
            }
        }
    }

    private func exportBackup() {
        do {
            exportDocument = BackupFile(backup: try BlockeyBackup.capture(context: context))
            isExporting = true
        } catch {
            backupMessage = "Could not read your tasks and templates to export."
        }
    }

    /// Decodes the chosen file and holds it until the user confirms.
    ///
    /// Reading the file here rather than after the confirmation means a file
    /// that is not a backup is rejected before the user is asked to destroy
    /// anything, so "Replace" is only ever offered for something restorable.
    private func stageRestore(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            // A file returned by the picker lives outside the sandbox.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let backup = try BlockeyBackup.decode(Data(contentsOf: url))
            pendingRestore = PendingRestore(
                backup: backup,
                existingTasks: (try? context.fetchCount(FetchDescriptor<TaskItem>())) ?? 0,
                existingTemplates: (try? context.fetchCount(FetchDescriptor<DayTemplate>())) ?? 0)
        } catch let error as BlockeyBackup.BackupError {
            backupMessage = error.localizedDescription
        } catch {
            backupMessage = "That file isn’t a Blockey backup."
        }
    }

    private func restore(_ pending: PendingRestore) {
        defer { pendingRestore = nil }
        do {
            let restored = try pending.backup.restore(into: context)
            backupMessage = "Restored \(restored.tasks) task\(restored.tasks == 1 ? "" : "s") and \(restored.templates) template\(restored.templates == 1 ? "" : "s")."
        } catch {
            backupMessage = "Could not restore that backup."
        }
    }

    #if DEBUG
    /// Plan task 0.3: the owner's on-phone check that a Thai category slug survives iCloud.
    /// Debug builds only, and hidden when the app runs on a Mac (see `canRunTokenProbe`).
    @ViewBuilder
    private var tokenProbeSection: some View {
        Section {
            if let probe = tokenProbe {
                Button("Check token test block") {
                    tokenProbeReport = probe.report(for: calendars.observeTokenProbe(probe))
                }
                Button("Delete token test block", role: .destructive) {
                    do {
                        let deleted = try calendars.deleteTokenProbe(probe)
                        TokenProbe.clear()
                        tokenProbe = nil
                        tokenProbeReport = deleted
                            ? "Test block deleted."
                            : "Test block not found, so nothing was deleted. If a block titled \"\(TokenProbe.title)\" is still in Calendar, delete it there."
                    } catch {
                        // Keep the probe so Delete can be tried again.
                        tokenProbeReport = "Could not delete it: \(error.localizedDescription)"
                    }
                }
            } else {
                Button("Create token test block") {
                    do {
                        let probe = try calendars.createTokenProbe()
                        probe.save()
                        tokenProbe = probe
                        tokenProbeReport = "Created \"\(TokenProbe.title)\" at the next whole hour.\n" + probe.report(for: calendars.observeTokenProbe(probe))
                    } catch {
                        tokenProbeReport = "Could not create it: \(error.localizedDescription)"
                    }
                }
            }
            if let tokenProbeReport {
                Text(tokenProbeReport)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        } header: {
            Text("Developer")
        } footer: {
            Text("Debug builds only. Writes one event to the Blockey calendar to test whether a Thai category survives iCloud sync.")
        }
    }
    #endif

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

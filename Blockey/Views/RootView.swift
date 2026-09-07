import SwiftUI

/// Gates the app on calendar access, because without it there is no day to show.
struct RootView: View {
    @Environment(CalendarService.self) private var calendars
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch calendars.access {
            case .granted:
                TodayView()
            case .undetermined:
                PermissionPrompt(state: .asking) {
                    await calendars.requestAccess()
                }
            case .denied, .restricted:
                PermissionPrompt(state: .blocked, action: nil)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // The user may have granted access in Settings while we were away.
            if phase == .active { calendars.refreshAccessStatus() }
        }
    }
}

private struct PermissionPrompt: View {
    enum State { case asking, blocked }

    let state: State
    var action: (() async -> Void)?

    @SwiftUI.State private var isRequesting = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.day.timeline.left")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(BlockCategory.deepWork.tint)

            Text("Blockey plans around your real day")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(state == .asking
                 ? "It needs access to your calendar to see your meetings, and to save your time blocks where the rest of your devices can see them."
                 : "Calendar access is off. Turn it on in Settings › Privacy & Security › Calendars › Blockey.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            if state == .asking, let action {
                Button {
                    isRequesting = true
                    _Concurrency.Task { await action(); isRequesting = false }
                } label: {
                    Text(isRequesting ? "Requesting…" : "Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isRequesting)
            } else {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(32)
    }
}

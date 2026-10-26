import SwiftData
import SwiftUI

@main
struct MyAlarmApp: App {
    private let container: ModelContainer
    @State private var scheduler = AlarmScheduler.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            container = try ModelContainer(for: AlarmTemplate.self, TemplateAlarm.self, ShiftReservation.self)
        } catch {
            fatalError("データベースを開けませんでした: \(error)")
        }
        SampleData.seedIfNeeded(container.mainContext)
        AlarmScheduler.shared.configure(container: container)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(scheduler)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: scheduler.requestSync()
            case .background: scheduler.scheduleAppRefresh()
            default: break
            }
        }
        .backgroundTask(.appRefresh(AlarmScheduler.refreshTaskID)) {
            await AlarmScheduler.shared.syncNow()
            await AlarmScheduler.shared.scheduleAppRefresh()
        }
    }
}

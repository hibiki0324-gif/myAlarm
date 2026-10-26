import SwiftData
import SwiftUI

/// アプリ全体で共有する SwiftData のコンテナ。アラームのボタンから起動されたときにも使う。
enum AppData {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: AlarmTemplate.self, TemplateAlarm.self, ShiftReservation.self, OneOffAlarm.self)
        } catch {
            fatalError("データベースを開けませんでした: \(error)")
        }
    }()
}

@main
struct MyAlarmApp: App {
    private let container = AppData.container
    @State private var scheduler = AlarmScheduler.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        SampleData.seedIfNeeded(container.mainContext)
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

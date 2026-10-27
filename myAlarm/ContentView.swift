import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AlarmScheduler.self) private var scheduler
    @Query private var templates: [AlarmTemplate]
    /// テンプレートのアラームの追加・削除も検知するため
    @Query private var templateAlarms: [TemplateAlarm]
    @Query private var reservations: [ShiftReservation]
    @Query private var oneOffs: [OneOffAlarm]

    var body: some View {
        TabView {
            Tab("予定", systemImage: "calendar") {
                ScheduleView()
            }
            Tab("テンプレート", systemImage: "square.stack.3d.up") {
                TemplateListView()
            }
        }
        .onChange(of: plannedAlarms) {
            scheduler.requestSync()
        }
    }

    /// 登録すべきアラームの一覧。これが変わったときだけ同期する。
    /// アラームに影響する値は PlannedAlarm に含まれるので、モデルに項目を足してもここを直す必要はない。
    private var plannedAlarms: [PlannedAlarm] {
        AlarmPlanner.plans(
            days: AlarmPlanner.horizonDays,
            templates: templates,
            reservations: reservations,
            oneOffs: oneOffs
        ).flatMap(\.alarms)
    }
}

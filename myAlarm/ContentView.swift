import SwiftData
import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("予定", systemImage: "calendar") {
                ScheduleView()
            }
            Tab("テンプレート", systemImage: "square.stack.3d.up") {
                TemplateListView()
            }
        }
        .background { AlarmSyncObserver() }
    }
}

/// 登録すべきアラームの一覧を見張り、変わったら同期を依頼する。何も表示しない。
/// データが変わるたびに描き直されるので、他の画面を巻き込まないよう独立したビューにしている。
private struct AlarmSyncObserver: View {
    @Environment(AlarmScheduler.self) private var scheduler
    @Query private var templates: [AlarmTemplate]
    /// テンプレートのアラームの追加・削除も検知するため
    @Query private var templateAlarms: [TemplateAlarm]
    @Query private var reservations: [ShiftReservation]
    @Query private var oneOffs: [OneOffAlarm]

    var body: some View {
        Color.clear
            .onChange(of: plannedAlarms) {
                scheduler.requestSync()
            }
    }

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

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AlarmScheduler.self) private var scheduler
    @Query private var templates: [AlarmTemplate]
    @Query private var alarms: [TemplateAlarm]
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
        .onChange(of: dataSignature) {
            scheduler.requestSync()
        }
    }

    /// アラームに影響するデータが変わったら同期するための指紋。
    private var dataSignature: Int {
        var hasher = Hasher()
        for template in templates.sorted(by: { $0.createdAt < $1.createdAt }) {
            hasher.combine(template.persistentModelID)
            hasher.combine(template.name)
            hasher.combine(template.colorName)
            hasher.combine(template.isActive)
            hasher.combine(template.wakeUpButtonText)
        }
        for alarm in alarms.sorted(by: { $0.persistentModelID.hashValue < $1.persistentModelID.hashValue }) {
            hasher.combine(alarm.persistentModelID)
            hasher.combine(alarm.hour)
            hasher.combine(alarm.minute)
            hasher.combine(alarm.label)
            hasher.combine(alarm.isEnabled)
            hasher.combine(alarm.template?.persistentModelID)
        }
        for reservation in reservations.sorted(by: { $0.day < $1.day }) {
            hasher.combine(reservation.day)
            hasher.combine(reservation.template?.persistentModelID)
        }
        for oneOff in oneOffs.sorted(by: { $0.persistentModelID.hashValue < $1.persistentModelID.hashValue }) {
            hasher.combine(oneOff.persistentModelID)
            hasher.combine(oneOff.day)
            hasher.combine(oneOff.hour)
            hasher.combine(oneOff.minute)
            hasher.combine(oneOff.label)
        }
        return hasher.finalize()
    }
}

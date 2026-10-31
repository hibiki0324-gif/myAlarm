import Foundation
import SwiftData

/// App Store 用のスクリーンショットを撮るときの表示モード。起動引数 `-demoMode` で有効になる。
/// データはメモリ上だけに持ち、AlarmKit には何も登録しない。Debug ビルドでしか有効にならない。
enum DemoMode {
    static let isEnabled: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-demoMode")
        #else
        false
        #endif
    }()

    /// 現在時刻。デモでは撮影日で見た目が変わらないよう、来月 8 日の 9:41 に固定する。
    static var now: Date {
        guard isEnabled else { return .now }
        let calendar = Calendar.current
        let thisMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: thisMonth) ?? thisMonth
        let day = calendar.date(byAdding: .day, value: 7, to: nextMonth) ?? nextMonth
        return calendar.date(bySettingHour: 9, minute: 41, second: 0, of: day) ?? day
    }

    /// デモ用のテンプレートと予定を入れる。
    static func seed(_ context: ModelContext) {
        #if DEBUG
        let day = AlarmTemplate(name: "日勤", color: .orange, isActive: true)
        let night = AlarmTemplate(name: "夜勤", color: .indigo)
        let late = AlarmTemplate(name: "遅番", color: .teal)
        let early = AlarmTemplate(name: "早番", color: .green)
        let training = AlarmTemplate(name: "研修", color: .blue)
        for template in [day, night, late, early, training] { context.insert(template) }

        day.wakeUpButtonText = "起きた！"
        day.alarms = [
            TemplateAlarm(hour: 5, minute: 30, label: "起床"),
            TemplateAlarm(hour: 5, minute: 40, label: "二度寝防止"),
            TemplateAlarm(hour: 5, minute: 50, label: "最後の砦"),
            TemplateAlarm(hour: 6, minute: 20, label: "出発の準備"),
        ]
        night.alarms = [
            TemplateAlarm(hour: 15, minute: 0, label: "起床"),
            TemplateAlarm(hour: 15, minute: 15, label: "二度寝防止"),
            TemplateAlarm(hour: 16, minute: 30, label: "出発の準備"),
        ]
        late.alarms = [
            TemplateAlarm(hour: 9, minute: 0, label: "起床"),
            TemplateAlarm(hour: 9, minute: 15, label: "二度寝防止"),
        ]

        early.alarms = [
            TemplateAlarm(hour: 4, minute: 30, label: "起床"),
            TemplateAlarm(hour: 4, minute: 40, label: "二度寝防止"),
            TemplateAlarm(hour: 5, minute: 0, label: "出発の準備"),
        ]
        training.alarms = [TemplateAlarm(hour: 7, minute: 0, label: "起床")]

        // 日日夜夜休休 の繰り返しを、今日が夜勤の 1 日目になるように並べる
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let monthStart = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let pattern: [AlarmTemplate?] = [day, day, night, night, nil, nil]
        for offset in 0..<62 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: monthStart) else { continue }
            let reservation = ShiftReservation(day: date)
            context.insert(reservation)
            reservation.template = pattern[(offset + 1) % pattern.count]
        }

        // 12 日（日勤）だけの追加アラーム
        if let extraDay = calendar.date(byAdding: .day, value: 11, to: monthStart) {
            context.insert(OneOffAlarm(day: extraDay, hour: 5, minute: 0, label: "早出の当番"))
            context.insert(OneOffAlarm(day: extraDay, hour: 5, minute: 10, label: "ごみ出し"))
        }
        try? context.save()
        #endif
    }
}

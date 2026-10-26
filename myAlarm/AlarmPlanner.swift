import Foundation

/// 1 日分の予定。予約 > 基本テンプレート の優先順で、その日に使うテンプレートを決める。
struct DayPlan: Identifiable {
    enum Source {
        /// 予約でテンプレートが指定されている
        case reserved
        /// 予約で「休み」が指定されている
        case off
        /// 予約がなく、基本テンプレートを使う
        case base
        /// 予約も基本テンプレートもない
        case none
    }

    let day: Date
    let source: Source
    let template: AlarmTemplate?
    let alarms: [PlannedAlarm]

    var id: Date { day }
}

struct PlannedAlarm: Hashable {
    let date: Date
    let title: String
    let color: TemplateColor
}

enum AlarmPlanner {
    /// AlarmKit に登録しておく日数。アプリを開くたびに先へ延長される。
    static let horizonDays = 14

    static func plans(
        days: Int,
        from now: Date = .now,
        templates: [AlarmTemplate],
        reservations: [ShiftReservation],
        calendar: Calendar = .current
    ) -> [DayPlan] {
        let today = calendar.startOfDay(for: now)
        let base = templates.first(where: \.isActive)
        let reservationByDay = Dictionary(
            reservations.map { (calendar.startOfDay(for: $0.day), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }

            let source: DayPlan.Source
            let template: AlarmTemplate?
            if let reservation = reservationByDay[day] {
                template = reservation.template
                source = template == nil ? .off : .reserved
            } else if let base {
                template = base
                source = .base
            } else {
                template = nil
                source = .none
            }

            let alarms = (template?.sortedAlarms ?? []).filter(\.isEnabled).compactMap { alarm -> PlannedAlarm? in
                guard let template,
                      let date = calendar.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: day)
                else { return nil }
                let title = alarm.label.isEmpty ? template.name : "\(template.name)・\(alarm.label)"
                return PlannedAlarm(date: date, title: title, color: template.color)
            }
            return DayPlan(day: day, source: source, template: template, alarms: alarms)
        }
    }
}

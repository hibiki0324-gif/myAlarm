import Foundation

/// 1 日分の予定。予約 > 基本テンプレート の優先順で、その日に使うテンプレートを決める。
/// 単発アラームはテンプレートのアラームに加えて鳴る。
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
    let oneOffs: [OneOffAlarm]
    /// テンプレートと単発のアラームを時刻順に並べたもの
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

    /// 「起きた」で止める範囲。この間隔以内で続けて鳴るアラームをひと続きとみなす。
    static let seriesGap: TimeInterval = 60 * 60

    /// anchor から seriesGap 以内の間隔で続けて鳴るアラームのうち、最後の時刻。
    /// 続くアラームがなければ anchor を返す。
    static func seriesEnd(from anchor: Date, in alarms: [PlannedAlarm]) -> Date {
        var last = anchor
        for alarm in alarms.sorted(by: { $0.date < $1.date }) where alarm.date >= anchor {
            guard alarm.date.timeIntervalSince(last) <= seriesGap else { break }
            last = alarm.date
        }
        return last
    }

    static func plans(
        days: Int,
        from now: Date = .now,
        templates: [AlarmTemplate],
        reservations: [ShiftReservation],
        oneOffs: [OneOffAlarm],
        calendar: Calendar = .current
    ) -> [DayPlan] {
        let today = calendar.startOfDay(for: now)
        let base = templates.first(where: \.isActive)
        let reservationByDay = Dictionary(
            reservations.map { (calendar.startOfDay(for: $0.day), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let oneOffsByDay = Dictionary(grouping: oneOffs) { calendar.startOfDay(for: $0.day) }

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

            let templateAlarms = (template?.sortedAlarms ?? []).filter(\.isEnabled).compactMap { alarm -> PlannedAlarm? in
                guard let template,
                      let date = calendar.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: day)
                else { return nil }
                let title = alarm.label.isEmpty ? template.name : "\(template.name)・\(alarm.label)"
                return PlannedAlarm(date: date, title: title, color: template.color)
            }
            let dayOneOffs = (oneOffsByDay[day] ?? []).sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
            let oneOffAlarms = dayOneOffs.compactMap { oneOff -> PlannedAlarm? in
                guard let date = calendar.date(bySettingHour: oneOff.hour, minute: oneOff.minute, second: 0, of: day) else { return nil }
                return PlannedAlarm(date: date, title: oneOff.title, color: OneOffAlarm.color)
            }
            let alarms = (templateAlarms + oneOffAlarms).sorted { $0.date < $1.date }
            return DayPlan(day: day, source: source, template: template, oneOffs: dayOneOffs, alarms: alarms)
        }
    }
}

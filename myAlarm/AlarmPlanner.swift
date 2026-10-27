import CryptoKit
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

/// AlarmKit に登録する 1 件分の内容。アラームの鳴り方に関わる値はすべてここに含める。
/// ここに含めておけば、変更の検知（ContentView）と登録 ID（alarmID）に自動で反映される。
struct PlannedAlarm: Hashable {
    let date: Date
    let title: String
    let color: TemplateColor
    /// 「起きた」ボタンの表示名
    let wakeUpButtonTitle: String

    /// 内容から決まる ID。内容が同じなら同期のたびに同じ ID になるので、変わった分だけ登録し直せる。
    var alarmID: UUID {
        let key = "\(date.timeIntervalSince1970)|\(title)|\(color.rawValue)|\(wakeUpButtonTitle)"
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // バージョン 5 相当
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 バリアント
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
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
                return PlannedAlarm(date: date, title: title, color: template.color, wakeUpButtonTitle: template.wakeUpButtonTitle)
            }
            let dayOneOffs = (oneOffsByDay[day] ?? []).sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
            let oneOffAlarms = dayOneOffs.compactMap { oneOff -> PlannedAlarm? in
                guard let date = calendar.date(bySettingHour: oneOff.hour, minute: oneOff.minute, second: 0, of: day) else { return nil }
                return PlannedAlarm(
                    date: date,
                    title: oneOff.title,
                    color: OneOffAlarm.color,
                    wakeUpButtonTitle: AlarmTemplate.defaultWakeUpButtonText
                )
            }
            let alarms = (templateAlarms + oneOffAlarms).sorted { $0.date < $1.date }
            return DayPlan(day: day, source: source, template: template, oneOffs: dayOneOffs, alarms: alarms)
        }
    }
}

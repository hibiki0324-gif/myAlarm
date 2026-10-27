import Foundation
import SwiftData
import SwiftUI

/// 複数のアラームをまとめたテンプレート（例: 日勤・夜勤）。
@Model
final class AlarmTemplate {
    var name: String
    var colorName: String
    /// 予約がない日に使われる「基本テンプレート」かどうか。同時に true になるのは 1 つだけ。
    var isActive: Bool
    var createdAt: Date
    /// アラームが鳴ったときの「起きた」ボタンの表示名。空なら「起きた」。
    var wakeUpButtonText: String = ""

    @Relationship(deleteRule: .cascade, inverse: \TemplateAlarm.template)
    var alarms: [TemplateAlarm] = []

    @Relationship(deleteRule: .cascade, inverse: \ShiftReservation.template)
    var reservations: [ShiftReservation] = []

    init(name: String, color: TemplateColor = .blue, isActive: Bool = false) {
        self.name = name
        self.colorName = color.rawValue
        self.isActive = isActive
        self.createdAt = .now
    }

    var color: TemplateColor {
        get { TemplateColor(rawValue: colorName) ?? .blue }
        set { colorName = newValue.rawValue }
    }

    static let defaultWakeUpButtonText = "起きた"

    var wakeUpButtonTitle: String {
        let text = wakeUpButtonText.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? Self.defaultWakeUpButtonText : text
    }

    var sortedAlarms: [TemplateAlarm] {
        alarms.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    var enabledAlarmTimes: String {
        let times = sortedAlarms.filter(\.isEnabled).map(\.timeText)
        return times.isEmpty ? "アラームなし" : times.joined(separator: "  ")
    }

    /// 同じ時刻のアラームがなければ追加する。
    func addAlarm(hour: Int, minute: Int, label: String = "", isEnabled: Bool = true) {
        guard !alarms.contains(where: { $0.hour == hour && $0.minute == minute }) else { return }
        alarms.append(TemplateAlarm(hour: hour, minute: minute, label: label, isEnabled: isEnabled))
    }

    /// 他のテンプレートのアラームを取り込む。同じ時刻のアラームは取り込まない。
    func importAlarms(from source: AlarmTemplate) {
        for alarm in source.sortedAlarms {
            addAlarm(hour: alarm.hour, minute: alarm.minute, label: alarm.label, isEnabled: alarm.isEnabled)
        }
    }
}

@Model
final class TemplateAlarm {
    var hour: Int
    var minute: Int
    var label: String
    var isEnabled: Bool
    var template: AlarmTemplate?

    init(hour: Int, minute: Int, label: String = "", isEnabled: Bool = true) {
        self.hour = hour
        self.minute = minute
        self.label = label
        self.isEnabled = isEnabled
    }

    var timeText: String { String(format: "%d:%02d", hour, minute) }
}

/// 特定の日に使うテンプレートの予約。template が nil の日は「休み（アラームなし）」。
@Model
final class ShiftReservation {
    /// その日の 0:00
    @Attribute(.unique) var day: Date
    var template: AlarmTemplate?

    init(day: Date) {
        self.day = day
    }
}

/// 特定の日だけ鳴る単発アラーム。その日のテンプレートのアラームに加えて鳴る。
@Model
final class OneOffAlarm {
    /// その日の 0:00
    var day: Date
    var hour: Int
    var minute: Int
    var label: String

    static let color: TemplateColor = .red

    init(day: Date, hour: Int, minute: Int, label: String = "") {
        self.day = day
        self.hour = hour
        self.minute = minute
        self.label = label
    }

    var timeText: String { String(format: "%d:%02d", hour, minute) }
    var title: String { label.isEmpty ? "単発アラーム" : label }
}

/// ある日に何を使うかの選択。
enum DayChoice: Hashable {
    /// 予約しない（基本テンプレートに従う）
    case base
    /// 休み（テンプレートのアラームなし）
    case off
    case template(AlarmTemplate)

    init(reservation: ShiftReservation?) {
        if let reservation {
            self = reservation.template.map(DayChoice.template) ?? .off
        } else {
            self = .base
        }
    }
}

enum ReservationEditor {
    /// 日ごとの選択を予約に反映する。同じ日の既存の予約は上書きする。
    static func apply(
        _ assignments: [(day: Date, choice: DayChoice)],
        reservations: [ShiftReservation],
        context: ModelContext,
        calendar: Calendar = .current
    ) {
        var byDay = Dictionary(
            reservations.map { (calendar.startOfDay(for: $0.day), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for (day, choice) in assignments {
            let day = calendar.startOfDay(for: day)
            switch choice {
            case .base:
                if let existing = byDay.removeValue(forKey: day) { context.delete(existing) }
            case .off, .template:
                let reservation: ShiftReservation
                if let existing = byDay[day] {
                    reservation = existing
                } else {
                    reservation = ShiftReservation(day: day)
                    context.insert(reservation)
                    byDay[day] = reservation
                }
                if case .template(let template) = choice {
                    reservation.template = template
                } else {
                    reservation.template = nil
                }
            }
        }
    }
}

enum TemplateColor: String, CaseIterable, Identifiable {
    case blue, orange, indigo, green, pink, teal, red, gray

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: .blue
        case .orange: .orange
        case .indigo: .indigo
        case .green: .green
        case .pink: .pink
        case .teal: .teal
        case .red: .red
        case .gray: .gray
        }
    }
}

enum WeekdayStyle {
    /// Calendar の weekday（1 = 日曜 … 7 = 土曜）に対応する文字色。
    static func color(for weekday: Int) -> Color {
        switch weekday {
        case 1: .red
        case 7: .blue
        default: .primary
        }
    }
}

/// 古くなった日付つきのデータ（日付ごとの指定と、この日だけのアラーム）を消す。
/// テンプレートとそのアラームは日付を持たないので対象外。
enum DataCleanup {
    /// この日より前のデータを消す。今月と先月の分は振り返れるように残す。
    static func cutoff(now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard let thisMonth = calendar.dateInterval(of: .month, for: now)?.start else { return nil }
        return calendar.date(byAdding: .month, value: -1, to: thisMonth)
    }

    static func removeExpired(now: Date = .now) {
        removeExpired(AppData.container.mainContext, now: now)
    }

    static func removeExpired(_ context: ModelContext, now: Date = .now) {
        guard let cutoff = cutoff(now: now) else { return }
        // テンプレートとの関連を正しく外すため、一括削除ではなく 1 件ずつ消す
        let reservations = (try? context.fetch(FetchDescriptor<ShiftReservation>(predicate: #Predicate { $0.day < cutoff }))) ?? []
        let oneOffs = (try? context.fetch(FetchDescriptor<OneOffAlarm>(predicate: #Predicate { $0.day < cutoff }))) ?? []
        guard !reservations.isEmpty || !oneOffs.isEmpty else { return }
        reservations.forEach(context.delete)
        oneOffs.forEach(context.delete)
        try? context.save()
    }
}

enum SampleData {
    /// 初回起動時に日勤・夜勤のサンプルを用意する（どちらも基本テンプレートにはしない）。
    static func seedIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<AlarmTemplate>())) ?? 0
        guard count == 0 else { return }

        let day = AlarmTemplate(name: "日勤", color: .orange)
        let night = AlarmTemplate(name: "夜勤", color: .indigo)
        context.insert(day)
        context.insert(night)
        day.alarms = [TemplateAlarm(hour: 6, minute: 0, label: "起床"), TemplateAlarm(hour: 6, minute: 10, label: "二度寝防止")]
        night.alarms = [TemplateAlarm(hour: 16, minute: 0, label: "起床"), TemplateAlarm(hour: 16, minute: 10, label: "二度寝防止")]
        try? context.save()
    }
}

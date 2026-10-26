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

    var sortedAlarms: [TemplateAlarm] {
        alarms.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    var enabledAlarmTimes: String {
        let times = sortedAlarms.filter(\.isEnabled).map(\.timeText)
        return times.isEmpty ? "アラームなし" : times.joined(separator: "  ")
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

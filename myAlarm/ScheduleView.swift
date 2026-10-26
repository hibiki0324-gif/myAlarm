import SwiftData
import SwiftUI

/// 基本テンプレートの一括切り替えと、日ごとの予約を行う画面。
struct ScheduleView: View {
    private static let visibleDays = 60

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(AlarmScheduler.self) private var scheduler
    @Query(sort: \AlarmTemplate.createdAt) private var templates: [AlarmTemplate]
    @Query private var reservations: [ShiftReservation]

    var body: some View {
        let plans = AlarmPlanner.plans(days: Self.visibleDays, templates: templates, reservations: reservations)

        NavigationStack {
            List {
                if scheduler.authorizationState == .denied {
                    Section {
                        Label("アラームが許可されていません", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Button("設定を開く") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                }

                Section {
                    nextAlarmView(plans: plans)
                }

                Section {
                    baseTemplateSwitcher
                } header: {
                    Text("基本テンプレート")
                } footer: {
                    Text("予約がない日はここで選んだテンプレートのアラームが鳴ります。")
                }

                Section {
                    ForEach(plans) { plan in
                        DayRow(plan: plan, templates: templates) { choice in
                            reserve(plan.day, choice)
                        }
                    }
                } header: {
                    Text("予定")
                } footer: {
                    footerText
                }
            }
            .navigationTitle("予定")
        }
    }

    @ViewBuilder
    private func nextAlarmView(plans: [DayPlan]) -> some View {
        if let next = plans.flatMap(\.alarms).first(where: { $0.date > .now }) {
            VStack(alignment: .leading, spacing: 4) {
                Text("次のアラーム")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(next.date, format: .dateTime.hour().minute())
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                    Text(next.date, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                }
                Text(next.title)
                    .foregroundStyle(next.color.color)
            }
        } else {
            Text("予定されているアラームはありません")
                .foregroundStyle(.secondary)
        }
    }

    private var baseTemplateSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(templates) { template in
                    switchButton(title: template.name, color: template.color.color, isSelected: template.isActive) {
                        setBase(template)
                    }
                }
                switchButton(title: "なし", color: .gray, isSelected: !templates.contains(where: \.isActive)) {
                    setBase(nil)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func switchButton(title: String, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .foregroundStyle(isSelected ? .white : color)
                .background(isSelected ? color : color.opacity(0.15), in: .capsule)
        }
        .buttonStyle(.borderless)
    }

    private var footerText: Text {
        if let error = scheduler.lastError {
            return Text("アラームの登録に失敗しました: \(error)")
        }
        if let until = scheduler.scheduledUntil {
            return Text("\(until.formatted(.dateTime.month().day()))までの\(scheduler.scheduledCount)件のアラームを登録済みです。それ以降の分は、アプリを開いたときやバックグラウンド更新で追加されます。")
        }
        return Text("今日から\(AlarmPlanner.horizonDays)日先までのアラームを登録します。")
    }

    private func setBase(_ template: AlarmTemplate?) {
        for t in templates {
            t.isActive = (t == template)
        }
    }

    private func reserve(_ day: Date, _ choice: DayRow.Choice) {
        let existing = reservations.first { Calendar.current.isDate($0.day, inSameDayAs: day) }
        switch choice {
        case .base:
            if let existing { context.delete(existing) }
        case .off, .template:
            let reservation = existing ?? {
                let new = ShiftReservation(day: day)
                context.insert(new)
                return new
            }()
            if case .template(let template) = choice {
                reservation.template = template
            } else {
                reservation.template = nil
            }
        }
    }
}

private struct DayRow: View {
    enum Choice {
        case base
        case off
        case template(AlarmTemplate)
    }

    let plan: DayPlan
    let templates: [AlarmTemplate]
    let onSelect: (Choice) -> Void

    var body: some View {
        Menu {
            Button("基本テンプレートに戻す", systemImage: "arrow.uturn.backward") { onSelect(.base) }
            Divider()
            ForEach(templates) { template in
                Button(template.name) { onSelect(.template(template)) }
            }
            Button("休み（アラームなし）", systemImage: "moon.zzz") { onSelect(.off) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.day, format: .dateTime.month().day().weekday(.abbreviated))
                        .foregroundStyle(weekdayColor)
                    if let relative = relativeDayText {
                        Text(relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 116, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(templateName)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .foregroundStyle(plan.template == nil ? Color.secondary : Color.white)
                            .background(chipColor, in: .capsule)
                        if plan.source == .reserved || plan.source == .off {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !plan.alarms.isEmpty {
                        Text(plan.alarms.map { $0.date.formatted(.dateTime.hour().minute()) }.joined(separator: "  "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Spacer()
            }
            .contentShape(.rect)
        }
        .tint(.primary)
    }

    private var templateName: String {
        switch plan.source {
        case .off: "休み"
        case .none: "なし"
        case .reserved, .base: plan.template?.name ?? ""
        }
    }

    private var chipColor: Color {
        plan.template?.color.color ?? Color.secondary.opacity(0.15)
    }

    private var relativeDayText: String? {
        let calendar = Calendar.current
        if calendar.isDateInToday(plan.day) { return "今日" }
        if calendar.isDateInTomorrow(plan.day) { return "明日" }
        return nil
    }

    private var weekdayColor: Color {
        switch Calendar.current.component(.weekday, from: plan.day) {
        case 1: .red
        case 7: .blue
        default: .primary
        }
    }
}

import SwiftData
import SwiftUI

/// 基本テンプレートの一括切り替えと、カレンダーで日ごとの予定を確認・変更する画面。
struct ScheduleView: View {
    @Environment(\.openURL) private var openURL
    @Environment(AlarmScheduler.self) private var scheduler
    @Query(sort: \AlarmTemplate.createdAt) private var templates: [AlarmTemplate]
    @Query private var reservations: [ShiftReservation]
    @Query private var oneOffs: [OneOffAlarm]

    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selectedDay: SelectedDay?
    @State private var isBulkApplyPresented = false

    var body: some View {
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
                    nextAlarmView
                }

                Section {
                    baseTemplateSwitcher
                } header: {
                    Text("基本テンプレート")
                } footer: {
                    Text("予約がない日はここで選んだテンプレートのアラームが鳴ります。")
                }

                Section {
                    MonthCalendarView(month: $month, plans: monthPlans) { day in
                        selectedDay = SelectedDay(day: day)
                    }
                } header: {
                    Text("予定")
                } footer: {
                    footerText
                }
            }
            .navigationTitle("予定")
            .toolbar {
                Button("まとめて設定", systemImage: "calendar.badge.plus") {
                    isBulkApplyPresented = true
                }
            }
            .sheet(item: $selectedDay) { selected in
                DayDetailSheet(day: selected.day)
            }
            .sheet(isPresented: $isBulkApplyPresented) {
                BulkApplySheet(initialDate: initialBulkDate)
            }
        }
    }

    private var monthPlans: [DayPlan] {
        let days = Calendar.current.range(of: .day, in: .month, for: month)?.count ?? 0
        return AlarmPlanner.plans(days: days, from: month, templates: templates, reservations: reservations, oneOffs: oneOffs)
    }

    /// 表示中の月が今月なら今日、それ以外ならその月の 1 日。
    private var initialBulkDate: Date {
        Calendar.current.isDate(month, equalTo: .now, toGranularity: .month) ? .now : month
    }

    @ViewBuilder
    private var nextAlarmView: some View {
        let plans = AlarmPlanner.plans(
            days: AlarmPlanner.horizonDays,
            templates: templates,
            reservations: reservations,
            oneOffs: oneOffs
        )
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
}

private struct SelectedDay: Identifiable {
    let day: Date
    var id: Date { day }
}

/// 1 か月分のカレンダー。各日にその日のテンプレートを表示する。
private struct MonthCalendarView: View {
    @Binding var month: Date
    let plans: [DayPlan]
    let onSelect: (Date) -> Void

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button("前の月", systemImage: "chevron.left") { moveMonth(by: -1) }
                    .labelStyle(.iconOnly)
                Spacer()
                Text(month, format: .dateTime.year().month(.wide))
                    .font(.headline)
                Spacer()
                Button("次の月", systemImage: "chevron.right") { moveMonth(by: 1) }
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .overlay(alignment: .trailing) {
                if !calendar.isDate(month, equalTo: .now, toGranularity: .month) {
                    Button("今日") {
                        month = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
                    }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                    .padding(.trailing, 36)
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 1)
                }
                ForEach(plans) { plan in
                    Button {
                        onSelect(plan.day)
                    } label: {
                        DayCell(plan: plan)
                    }
                    .buttonStyle(.borderless)
                    .tint(.primary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var leadingBlanks: Int {
        let weekday = calendar.component(.weekday, from: month)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private func moveMonth(by value: Int) {
        if let moved = calendar.date(byAdding: .month, value: value, to: month) {
            month = moved
        }
    }
}

private struct DayCell: View {
    let plan: DayPlan

    private var calendar: Calendar { .current }

    var body: some View {
        VStack(spacing: 3) {
            Text("\(calendar.component(.day, from: plan.day))")
                .font(.callout.weight(isToday ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(isToday ? Color.white : weekdayColor)
                .frame(width: 28, height: 28)
                .background(isToday ? Color.accentColor : .clear, in: .circle)

            templateChip
                .frame(height: 16)

            Image(systemName: "bell.fill")
                .font(.system(size: 8))
                .foregroundStyle(OneOffAlarm.color.color)
                .opacity(plan.oneOffs.isEmpty ? 0 : 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .contentShape(.rect)
        .opacity(isPast ? 0.4 : 1)
    }

    /// 予約した日は塗りつぶし、基本テンプレートの日は薄い色で表示する。
    @ViewBuilder
    private var templateChip: some View {
        switch plan.source {
        case .reserved, .base:
            if let template = plan.template {
                let isReserved = plan.source == .reserved
                Text(template.name)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 3)
                    .frame(maxWidth: .infinity, minHeight: 16)
                    .foregroundStyle(isReserved ? Color.white : template.color.color)
                    .background(template.color.color.opacity(isReserved ? 1 : 0.18), in: .rect(cornerRadius: 4))
            }
        case .off:
            Text("休み")
                .font(.system(size: 10, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 16)
                .foregroundStyle(.secondary)
                .background(Color.secondary.opacity(0.15), in: .rect(cornerRadius: 4))
        case .none:
            Color.clear
        }
    }

    private var isToday: Bool { calendar.isDateInToday(plan.day) }

    private var isPast: Bool { plan.day < calendar.startOfDay(for: .now) }

    private var weekdayColor: Color {
        switch calendar.component(.weekday, from: plan.day) {
        case 1: .red
        case 7: .blue
        default: .primary
        }
    }
}

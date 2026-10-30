import SwiftData
import SwiftUI

/// 週・月・期間を指定して、テンプレートや繰り返しパターン、曜日指定でまとめて予約するシート。
struct BulkApplySheet: View {
    enum RangeUnit: String, CaseIterable, Identifiable {
        case week = "週"
        case month = "月"
        case custom = "期間"

        var id: Self { self }
    }

    enum Mode: String, CaseIterable, Identifiable {
        case single = "同じ内容"
        case pattern = "パターン"
        case weekday = "曜日を選ぶ"

        var id: Self { self }
    }

    /// パターンの 1 日分。行の追加・削除で取り違えないよう、ID を持たせる。
    private struct PatternStep: Identifiable {
        let id = UUID()
        var choice: DayChoice
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AlarmTemplate.createdAt) private var templates: [AlarmTemplate]
    @Query private var reservations: [ShiftReservation]

    @State private var unit: RangeUnit = .week
    @State private var date: Date
    @State private var endDate: Date
    @State private var mode: Mode = .single
    @State private var single: DayChoice = .off
    @State private var pattern: [PatternStep] = []
    /// Calendar の weekday（1 = 日曜 … 7 = 土曜）。初期値は月〜金。
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var weekdayChoice: DayChoice = .off

    private let calendar = Calendar.current

    init(initialDate: Date) {
        _date = State(initialValue: initialDate)
        _endDate = State(initialValue: Calendar.current.date(byAdding: .day, value: 13, to: initialDate) ?? initialDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("単位", selection: $unit) {
                        ForEach(RangeUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch unit {
                    case .week:
                        DatePicker("この日を含む週", selection: $date, displayedComponents: .date)
                    case .month:
                        DatePicker("この日を含む月", selection: $date, displayedComponents: .date)
                    case .custom:
                        DatePicker("開始日", selection: $date, displayedComponents: .date)
                        DatePicker("終了日", selection: $endDate, in: date..., displayedComponents: .date)
                    }
                } header: {
                    Text("範囲")
                } footer: {
                    Text(rangeText)
                }

                Section {
                    Picker("内容", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .single:
                        choicePicker("設定する内容", selection: $single)
                    case .pattern:
                        ForEach($pattern) { $step in
                            let index = pattern.firstIndex { $0.id == step.id } ?? 0
                            choicePicker("\(index + 1)日目", selection: $step.choice)
                        }
                        .onDelete { pattern.remove(atOffsets: $0) }
                        Button("日を追加", systemImage: "plus.circle.fill") {
                            pattern.append(PatternStep(choice: pattern.last?.choice ?? .off))
                        }
                    case .weekday:
                        weekdayToggles
                        choicePicker("設定する内容", selection: $weekdayChoice)
                    }
                } header: {
                    Text("設定する内容")
                } footer: {
                    Text(contentFooter)
                }
            }
            .navigationTitle("まとめて設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("適用", systemImage: "checkmark") {
                        apply()
                        dismiss()
                    }
                    .disabled(assignments.isEmpty)
                }
            }
            .onAppear {
                if pattern.isEmpty, let first = templates.first {
                    pattern = [.template(first), .template(first), .off].map { PatternStep(choice: $0) }
                    weekdayChoice = .template(first)
                }
                if DemoMode.isEnabled, templates.count >= 2 {
                    let (day, night) = (DayChoice.template(templates[0]), DayChoice.template(templates[1]))
                    pattern = [day, day, night, night, .off, .off].map { PatternStep(choice: $0) }
                }
            }
        }
    }

    private func choicePicker(_ title: String, selection: Binding<DayChoice>) -> some View {
        Picker(title, selection: selection) {
            ForEach(templates) { template in
                Text(template.name).tag(DayChoice.template(template))
            }
            Text("休み").tag(DayChoice.off)
            Text("基本テンプレートに戻す").tag(DayChoice.base)
        }
    }

    private var weekdayToggles: some View {
        let calendar = calendar
        let symbols = calendar.veryShortWeekdaySymbols
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        return HStack {
            ForEach(order, id: \.self) { weekday in
                let isOn = weekdays.contains(weekday)
                Button {
                    if isOn {
                        weekdays.remove(weekday)
                    } else {
                        weekdays.insert(weekday)
                    }
                } label: {
                    Text(symbols[weekday - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(isOn ? Color.white : WeekdayStyle.color(for: weekday))
                        .background(isOn ? Color.accentColor : Color.secondary.opacity(0.12), in: .circle)
                }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }

    /// 範囲内のすべての日（今日より前も含む）。パターンは範囲の初日から数える。
    private var rangeDays: [Date] {
        let start: Date
        let count: Int
        switch unit {
        case .week, .month:
            guard let interval = calendar.dateInterval(of: unit == .week ? .weekOfYear : .month, for: date) else { return [] }
            start = interval.start
            count = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
        case .custom:
            start = calendar.startOfDay(for: date)
            count = (calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: endDate)).day ?? 0) + 1
        }
        return (0..<max(count, 0)).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var editableDays: [Date] {
        let today = calendar.startOfDay(for: .now)
        return rangeDays.filter { $0 >= today }
    }

    /// 実際に書き込む日と内容。今日より前の日は含めない。
    private var assignments: [(day: Date, choice: DayChoice)] {
        let today = calendar.startOfDay(for: .now)
        let all: [(day: Date, choice: DayChoice)]
        switch mode {
        case .single:
            all = rangeDays.map { (day: $0, choice: single) }
        case .pattern:
            guard !pattern.isEmpty else { return [] }
            all = rangeDays.enumerated().map { (day: $0.element, choice: pattern[$0.offset % pattern.count].choice) }
        case .weekday:
            all = rangeDays
                .filter { weekdays.contains(calendar.component(.weekday, from: $0)) }
                .map { (day: $0, choice: weekdayChoice) }
        }
        return all.filter { $0.day >= today }
    }

    private var rangeText: String {
        let days = rangeDays
        guard let first = days.first, let last = days.last else { return "" }
        let format = Date.FormatStyle.dateTime.month().day().weekday(.abbreviated)
        var text = "\(first.formatted(format))〜\(last.formatted(format))（\(days.count)日間）"
        let skipped = days.count - editableDays.count
        if skipped > 0 {
            text += "\n今日より前の\(skipped)日は変更しません。"
        }
        return text
    }

    private var contentFooter: String {
        switch mode {
        case .single:
            "範囲内のすべての日に設定します。すでにある予約は上書きされます。"
        case .pattern:
            "範囲の初日から順に、パターンを繰り返して設定します（例: 日勤・日勤・夜勤・夜勤・休み・休み）。すでにある予約は上書きされます。"
        case .weekday:
            "選んだ曜日に設定します。選んでいない曜日は変更しません。すでにある予約は上書きされます。"
        }
    }

    private func apply() {
        ReservationEditor.apply(assignments, reservations: reservations, context: context)
    }
}

import SwiftData
import SwiftUI

/// 週・月・期間を指定して、テンプレートや繰り返しパターンをまとめて予約するシート。
struct BulkApplySheet: View {
    enum RangeUnit: String, CaseIterable, Identifiable {
        case week = "週"
        case month = "月"
        case custom = "期間"

        var id: Self { self }
    }

    enum Mode: String, CaseIterable, Identifiable {
        case single = "同じ内容"
        case pattern = "繰り返しパターン"

        var id: Self { self }
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
    @State private var pattern: [DayChoice] = []

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
                        ForEach(pattern.indices, id: \.self) { index in
                            choicePicker("\(index + 1)日目", selection: $pattern[index])
                        }
                        .onDelete { pattern.remove(atOffsets: $0) }
                        Button("日を追加", systemImage: "plus.circle.fill") {
                            pattern.append(pattern.last ?? .off)
                        }
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
                    .disabled(choices.isEmpty || editableDays.isEmpty)
                }
            }
            .onAppear {
                if pattern.isEmpty, let first = templates.first {
                    pattern = [.template(first), .template(first), .off]
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

    private var choices: [DayChoice] {
        mode == .single ? [single] : pattern
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
        }
    }

    private func apply() {
        let choices = choices
        guard !choices.isEmpty else { return }
        let today = calendar.startOfDay(for: .now)
        let assignments = rangeDays.enumerated()
            .filter { $0.element >= today }
            .map { (day: $0.element, choice: choices[$0.offset % choices.count]) }
        ReservationEditor.apply(assignments, reservations: reservations, context: context)
    }
}

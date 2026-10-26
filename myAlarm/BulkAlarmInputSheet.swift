import SwiftUI

/// 開始時刻から終了時刻まで、指定した分おきにアラームをまとめて作るシート。
struct BulkAlarmInputSheet: View {
    /// 一度に追加できる件数の上限。誤って大量に作らないようにする。
    static let maxCount = 60
    static let intervals = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120]

    private enum TimeField {
        case start, end
    }

    @Environment(\.dismiss) private var dismiss
    let onSave: (_ times: [(hour: Int, minute: Int)], _ label: String) -> Void

    @State private var start = Self.time(hour: 6, minute: 0)
    @State private var end = Self.time(hour: 6, minute: 30)
    @State private var interval = 5
    @State private var label = ""
    @State private var expanded: TimeField?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    timeRow("開始時刻", selection: $start, field: .start)
                    timeRow("終了時刻", selection: $end, field: .end)
                    Picker("間隔", selection: $interval) {
                        ForEach(Self.intervals, id: \.self) { minutes in
                            Text("\(minutes)分おき").tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                    TextField("ラベル（任意）", text: $label)
                } footer: {
                    Text(summary)
                }
            }
            .navigationTitle("まとめて追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加", systemImage: "checkmark") {
                        onSave(times, label)
                        dismiss()
                    }
                    .disabled(times.isEmpty || times.count > Self.maxCount)
                }
            }
        }
        .presentationDetents([.large])
    }

    /// タップするとホイールが開き、「決定」で閉じる時刻の行。
    @ViewBuilder
    private func timeRow(_ title: String, selection: Binding<Date>, field: TimeField) -> some View {
        let isExpanded = expanded == field
        Button {
            withAnimation { expanded = isExpanded ? nil : field }
        } label: {
            LabeledContent(title) {
                Text(selection.wrappedValue, format: .dateTime.hour().minute())
                    .monospacedDigit()
                    .foregroundStyle(isExpanded ? Color.accentColor : Color.primary)
            }
        }
        .tint(.primary)
        if isExpanded {
            DatePicker(title, selection: selection, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            Button("決定", systemImage: "checkmark.circle.fill") {
                withAnimation { expanded = nil }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// 開始から終了まで（終了時刻を含む）の時刻。日をまたぐ指定は扱わない。
    private var times: [(hour: Int, minute: Int)] {
        let startMinutes = Self.minutes(of: start)
        let endMinutes = Self.minutes(of: end)
        guard startMinutes <= endMinutes else { return [] }
        return stride(from: startMinutes, through: endMinutes, by: interval).map { (hour: $0 / 60, minute: $0 % 60) }
    }

    private var summary: String {
        if Self.minutes(of: start) > Self.minutes(of: end) {
            return "終了時刻は開始時刻より後にしてください（日をまたぐ指定はできません）。"
        }
        let times = times
        if times.count > Self.maxCount {
            return "\(times.count)件になります。一度に追加できるのは\(Self.maxCount)件までです。"
        }
        let list = times.map { String(format: "%d:%02d", $0.hour, $0.minute) }.joined(separator: "  ")
        return "\(times.count)件: \(list)\n同じ時刻のアラームがすでにある場合は追加しません。"
    }

    private static func time(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
    }

    private static func minutes(of date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

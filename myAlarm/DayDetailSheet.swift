import SwiftData
import SwiftUI

/// 1 日分の予定を編集するシート。テンプレートの予約と、その日だけの単発アラームを扱う。
struct DayDetailSheet: View {
    let day: Date

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AlarmTemplate.createdAt) private var templates: [AlarmTemplate]
    @Query private var reservations: [ShiftReservation]
    @Query private var oneOffs: [OneOffAlarm]
    @State private var editing: AlarmEditTarget<OneOffAlarm>?
    @State private var isBulkInputPresented = false
    @State private var isBulkLabelPresented = false
    @State private var isSelecting = false
    @State private var selection: Set<PersistentIdentifier> = []

    var body: some View {
        let plan = AlarmPlanner.plans(days: 1, from: day, templates: templates, reservations: reservations, oneOffs: oneOffs).first

        NavigationStack {
            Form {
                Section {
                    choiceRow(.base, title: baseTitle)
                    ForEach(templates) { template in
                        choiceRow(.template(template), title: template.name, color: template.color.color)
                    }
                    choiceRow(.off, title: "休み（アラームなし）")
                } header: {
                    Text("テンプレート")
                }

                Section {
                    let alarms = plan?.template?.sortedAlarms.filter(\.isEnabled) ?? []
                    if alarms.isEmpty {
                        Text("なし")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(alarms) { alarm in
                        LabeledContent {
                            Text(alarm.label)
                        } label: {
                            Text(alarm.timeText)
                                .font(.title3)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("テンプレートのアラーム")
                } footer: {
                    Text("テンプレートの内容は「テンプレート」タブで変更できます。")
                }

                Section {
                    ForEach(plan?.oneOffs ?? []) { oneOff in
                        if isSelecting {
                            let id = oneOff.persistentModelID
                            SelectableRow(isSelected: selection.contains(id)) {
                                selection.formSymmetricDifference([id])
                            } content: {
                                oneOffLabel(oneOff)
                            }
                        } else {
                            oneOffLabel(oneOff)
                                .contentShape(.rect)
                                .onTapGesture { editing = .existing(oneOff) }
                        }
                    }
                    .onDelete { offsets in
                        let sorted = plan?.oneOffs ?? []
                        for index in offsets { context.delete(sorted[index]) }
                    }
                    .deleteDisabled(isSelecting)
                    if !isSelecting {
                        Button("アラームを追加", systemImage: "plus.circle.fill") {
                            editing = .new
                        }
                        Button("時間帯でまとめて追加", systemImage: "list.bullet.indent") {
                            isBulkInputPresented = true
                        }
                        if !(plan?.oneOffs ?? []).isEmpty {
                            Button("ラベルをまとめて設定", systemImage: "tag") {
                                isBulkLabelPresented = true
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("この日だけのアラーム")
                        Spacer()
                        if isSelecting || !(plan?.oneOffs ?? []).isEmpty {
                            Button(isSelecting ? "選択をやめる" : "選択") {
                                isSelecting.toggle()
                                selection = []
                            }
                            .font(.subheadline)
                            .textCase(nil)
                        }
                    }
                } footer: {
                    Text("テンプレートのアラームに加えて鳴ります。")
                }
            }
            .navigationTitle(day.formatted(.dateTime.month().day().weekday(.abbreviated)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了", systemImage: "checkmark") { dismiss() }
                }
            }
            .selectionDeleteBar(
                isSelecting: isSelecting,
                selection: $selection,
                allIDs: { (plan?.oneOffs ?? []).map(\.persistentModelID) }
            ) {
                for oneOff in plan?.oneOffs ?? [] where selection.contains(oneOff.persistentModelID) {
                    context.delete(oneOff)
                }
                selection = []
                isSelecting = false
            }
            .sheet(item: $editing) { target in
                switch target {
                case .new:
                    AlarmEditSheet(isNew: true) { hour, minute, label in
                        context.insert(OneOffAlarm(day: Calendar.current.startOfDay(for: day), hour: hour, minute: minute, label: label))
                    }
                case .existing(let oneOff):
                    AlarmEditSheet(isNew: false, hour: oneOff.hour, minute: oneOff.minute, label: oneOff.label) { hour, minute, label in
                        oneOff.hour = hour
                        oneOff.minute = minute
                        oneOff.label = label
                    }
                }
            }
            .sheet(isPresented: $isBulkInputPresented) {
                BulkAlarmInputSheet { times, label in
                    addOneOffs(times, label: label)
                }
            }
            .bulkLabelAlert(isPresented: $isBulkLabelPresented, message: "この日だけのアラームのラベルを変更します。") { label, onlyEmpty in
                for oneOff in oneOffs where Calendar.current.isDate(oneOff.day, inSameDayAs: day) && (!onlyEmpty || oneOff.label.isEmpty) {
                    oneOff.label = label
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// 同じ時刻の単発アラームがなければ追加する。
    private func addOneOffs(_ times: [(hour: Int, minute: Int)], label: String) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let existing = Set(oneOffs.filter { calendar.isDate($0.day, inSameDayAs: day) }.map { $0.hour * 60 + $0.minute })
        for time in times where !existing.contains(time.hour * 60 + time.minute) {
            context.insert(OneOffAlarm(day: start, hour: time.hour, minute: time.minute, label: label))
        }
    }

    private func oneOffLabel(_ oneOff: OneOffAlarm) -> some View {
        LabeledContent {
            Text(oneOff.label)
        } label: {
            Text(oneOff.timeText)
                .font(.title3)
                .monospacedDigit()
        }
    }

    private var currentChoice: DayChoice {
        DayChoice(reservation: reservations.first { Calendar.current.isDate($0.day, inSameDayAs: day) })
    }

    private var baseTitle: String {
        if let base = templates.first(where: \.isActive) {
            return "基本テンプレート（\(base.name)）"
        }
        return "基本テンプレート（なし）"
    }

    private func choiceRow(_ choice: DayChoice, title: String, color: Color? = nil) -> some View {
        Button {
            ReservationEditor.apply([(day, choice)], reservations: reservations, context: context)
        } label: {
            HStack {
                if let color {
                    Circle()
                        .fill(color)
                        .frame(width: 12, height: 12)
                }
                Text(title)
                Spacer()
                if currentChoice == choice {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .tint(.primary)
    }
}

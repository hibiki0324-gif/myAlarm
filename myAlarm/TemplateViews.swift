import SwiftData
import SwiftUI

struct TemplateListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AlarmTemplate.createdAt) private var templates: [AlarmTemplate]
    @State private var path: [AlarmTemplate] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(templates) { template in
                    NavigationLink(value: template) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(template.color.color)
                                .frame(width: 14, height: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                    .font(.headline)
                                Text(template.enabledAlarmTimes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Spacer()
                            if template.isActive {
                                Text("基本")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(templates[index]) }
                }
            }
            .overlay {
                if templates.isEmpty {
                    ContentUnavailableView("テンプレートがありません", systemImage: "square.stack.3d.up", description: Text("右上の＋から作成できます"))
                }
            }
            .navigationTitle("テンプレート")
            .navigationDestination(for: AlarmTemplate.self) { template in
                TemplateEditView(template: template)
            }
            .toolbar {
                Button("追加", systemImage: "plus") {
                    let used = Set(templates.map(\.color))
                    let template = AlarmTemplate(
                        name: "新しいテンプレート",
                        color: TemplateColor.allCases.first { !used.contains($0) } ?? .blue
                    )
                    context.insert(template)
                    path.append(template)
                }
            }
        }
    }
}

struct TemplateEditView: View {
    @Environment(\.modelContext) private var context
    @Bindable var template: AlarmTemplate
    @State private var editing: AlarmEditTarget?

    var body: some View {
        Form {
            Section("名前") {
                TextField("例: 日勤", text: $template.name)
            }

            Section("色") {
                HStack {
                    ForEach(TemplateColor.allCases) { color in
                        Circle()
                            .fill(color.color)
                            .frame(width: 30, height: 30)
                            .overlay {
                                if template.color == color {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .onTapGesture { template.color = color }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("アラーム") {
                ForEach(template.sortedAlarms) { alarm in
                    AlarmRow(alarm: alarm)
                        .contentShape(.rect)
                        .onTapGesture { editing = .existing(alarm) }
                }
                .onDelete { offsets in
                    let sorted = template.sortedAlarms
                    for index in offsets { context.delete(sorted[index]) }
                }
                Button("アラームを追加", systemImage: "plus.circle.fill") {
                    editing = .new
                }
            }
        }
        .navigationTitle(template.name.isEmpty ? "テンプレート" : template.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { target in
            AlarmEditSheet(template: template, target: target)
        }
    }
}

private struct AlarmRow: View {
    @Bindable var alarm: TemplateAlarm

    var body: some View {
        Toggle(isOn: $alarm.isEnabled) {
            VStack(alignment: .leading) {
                Text(alarm.timeText)
                    .font(.system(size: 36, weight: .light, design: .rounded))
                    .monospacedDigit()
                if !alarm.label.isEmpty {
                    Text(alarm.label)
                        .font(.caption)
                }
            }
            .foregroundStyle(alarm.isEnabled ? .primary : .secondary)
        }
    }
}

enum AlarmEditTarget: Identifiable {
    case new
    case existing(TemplateAlarm)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let alarm): "\(alarm.persistentModelID.hashValue)"
        }
    }
}

private struct AlarmEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let template: AlarmTemplate
    let target: AlarmEditTarget

    @State private var time: Date
    @State private var label: String

    init(template: AlarmTemplate, target: AlarmEditTarget) {
        self.template = template
        self.target = target
        var components = DateComponents()
        switch target {
        case .new:
            components.hour = 7
            components.minute = 0
            _label = State(initialValue: "")
        case .existing(let alarm):
            components.hour = alarm.hour
            components.minute = alarm.minute
            _label = State(initialValue: alarm.label)
        }
        _time = State(initialValue: Calendar.current.date(from: components) ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("時刻", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                TextField("ラベル（任意）", text: $label)
            }
            .navigationTitle(isNew ? "アラームを追加" : "アラームを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", systemImage: "checkmark") {
                        save()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    private func save() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        switch target {
        case .new:
            template.alarms.append(TemplateAlarm(hour: hour, minute: minute, label: label))
        case .existing(let alarm):
            alarm.hour = hour
            alarm.minute = minute
            alarm.label = label
        }
    }
}

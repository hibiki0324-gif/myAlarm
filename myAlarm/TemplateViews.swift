import SwiftData
import SwiftUI

struct TemplateListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AlarmTemplate.createdAt) private var templates: [AlarmTemplate]
    @State private var path: [AlarmTemplate] = []
    /// 作成中（まだ保存していない）のテンプレート
    @State private var draftID: PersistentIdentifier?
    @State private var pendingDelete: AlarmTemplate?

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
                    pendingDelete = offsets.first.map { templates[$0] }
                }
            }
            .confirmationDialog(
                "「\(pendingDelete?.name ?? "")」を削除しますか？",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { template in
                Button("削除", role: .destructive) { context.delete(template) }
            } message: { template in
                Text(deleteMessage(for: template))
            }
            .overlay {
                if templates.isEmpty {
                    ContentUnavailableView("テンプレートがありません", systemImage: "square.stack.3d.up", description: Text("右上の＋から作成できます"))
                }
            }
            .navigationTitle("テンプレート")
            .navigationDestination(for: AlarmTemplate.self) { template in
                TemplateEditView(template: template, isNew: template.persistentModelID == draftID)
            }
            .onChange(of: path) {
                if path.isEmpty { draftID = nil }
            }
            .toolbar {
                Menu("追加", systemImage: "plus") {
                    Button("新規作成", systemImage: "plus") { create(copying: nil) }
                    if !templates.isEmpty {
                        Section("コピーして作成") {
                            ForEach(templates) { template in
                                Button(template.name) { create(copying: template) }
                            }
                        }
                    }
                }
            }
        }
    }

    /// 削除するとどうなるかの説明。予約と基本テンプレートへの影響を伝える。
    private func deleteMessage(for template: AlarmTemplate) -> String {
        var lines: [String] = []
        let today = Calendar.current.startOfDay(for: .now)
        let reservedDays = template.reservations.filter { $0.day >= today }.count
        if reservedDays > 0 {
            lines.append("このテンプレートを予約している今日以降の\(reservedDays)日は、予約が解除されて基本テンプレートに従います。")
        }
        if template.isActive {
            lines.append("基本テンプレートは「なし」になります。")
        }
        lines.append("この操作は取り消せません。")
        return lines.joined(separator: "\n")
    }

    /// source を渡すと、そのアラームを引き継いだテンプレートを作る。色はまだ使っていない色にする。
    private func create(copying source: AlarmTemplate?) {
        let used = Set(templates.map(\.color))
        let template = AlarmTemplate(
            name: source.map { "\($0.name)のコピー" } ?? "新しいテンプレート",
            color: TemplateColor.allCases.first { !used.contains($0) } ?? .blue
        )
        context.insert(template)
        if let source {
            template.wakeUpButtonText = source.wakeUpButtonText
            template.importAlarms(from: source)
        }
        draftID = template.persistentModelID
        path.append(template)
    }
}

struct TemplateEditView: View {
    private enum Field {
        case name, wakeUpButton
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var template: AlarmTemplate
    /// 新規作成中なら、「保存」を押すまでテンプレートを確定しない
    var isNew = false
    @Query(sort: \AlarmTemplate.createdAt) private var templates: [AlarmTemplate]
    @State private var editing: AlarmEditTarget<TemplateAlarm>?
    @State private var isBulkInputPresented = false
    @State private var isBulkLabelPresented = false
    @State private var isSelecting = false
    @State private var selection: Set<PersistentIdentifier> = []
    @FocusState private var focusedField: Field?
    @State private var initialSnapshot: TemplateSnapshot?
    /// 入力中の文字。1 文字ごとにモデルを書き換えると関係する画面がすべて描き直されるので、確定時にまとめて反映する。
    @State private var nameDraft = ""
    @State private var wakeUpDraft = ""
    @State private var isDiscardConfirming = false
    @State private var isDiscarded = false

    var body: some View {
        Form {
            Section("名前") {
                TextField("例: 日勤", text: $nameDraft)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.done)
                    .onSubmit(commitDrafts)
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
                            .onTapGesture {
                                focusedField = nil
                                template.color = color
                            }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("アラーム") {
                // 並べ替えたアラームの一覧は、描画 1 回につき 1 度だけ作る
                let alarms = template.sortedAlarms
                ForEach(alarms) { alarm in
                    if isSelecting {
                        let id = alarm.persistentModelID
                        SelectableRow(isSelected: selection.contains(id)) {
                            selection.formSymmetricDifference([id])
                        } content: {
                            AlarmTimeLabel(timeText: alarm.timeText, label: alarm.label, isEnabled: alarm.isEnabled)
                        }
                    } else {
                        AlarmRow(alarm: alarm)
                            .contentShape(.rect)
                            .onTapGesture { editing = .existing(alarm) }
                            .simultaneousGesture(TapGesture().onEnded { focusedField = nil })
                    }
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(alarms[index]) }
                }
                .deleteDisabled(isSelecting)
                if !isSelecting {
                    alarmActions(hasAlarms: !alarms.isEmpty)
                }
            }

            Section {
                TextField(AlarmTemplate.defaultWakeUpButtonText, text: $wakeUpDraft)
                    .focused($focusedField, equals: .wakeUpButton)
                    .submitLabel(.done)
                    .onSubmit(commitDrafts)
            } header: {
                Text("一括停止ボタンの表示名")
            } footer: {
                Text("アラームが鳴ったときに表示される、続けて鳴る予定のアラームをまとめて止めるボタンの文字です。空欄なら「起きた」になります。長いと途中で切れることがあるので、短めがおすすめです。")
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle(nameDraft.isEmpty ? "テンプレート" : nameDraft)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isNew)
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { cancelNew() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        commitDrafts()
                        dismiss()
                    }
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") { focusedField = nil }
            }
            if isSelecting || !template.alarms.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(isSelecting ? "完了" : "選択") {
                        focusedField = nil
                        isSelecting.toggle()
                        selection = []
                    }
                }
            }
        }
        .selectionDeleteBar(
            isSelecting: isSelecting,
            selection: $selection,
            allIDs: { template.alarms.map(\.persistentModelID) }
        ) {
            for alarm in template.alarms where selection.contains(alarm.persistentModelID) {
                context.delete(alarm)
            }
            selection = []
            isSelecting = false
        }
        .sheet(item: $editing) { target in
            switch target {
            case .new:
                AlarmEditSheet(isNew: true) { hour, minute, label in
                    template.alarms.append(TemplateAlarm(hour: hour, minute: minute, label: label))
                }
            case .existing(let alarm):
                AlarmEditSheet(isNew: false, hour: alarm.hour, minute: alarm.minute, label: alarm.label) { hour, minute, label in
                    alarm.hour = hour
                    alarm.minute = minute
                    alarm.label = label
                }
            }
        }
        .sheet(isPresented: $isBulkInputPresented) {
            BulkAlarmInputSheet { times, label in
                for time in times {
                    template.addAlarm(hour: time.hour, minute: time.minute, label: label)
                }
            }
        }
        .bulkLabelAlert(isPresented: $isBulkLabelPresented, message: "このテンプレートのアラームのラベルを変更します。") { label, onlyEmpty in
            for alarm in template.alarms where !onlyEmpty || alarm.label.isEmpty {
                alarm.label = label
            }
        }
        .confirmationDialog("変更内容を破棄しますか？", isPresented: $isDiscardConfirming, titleVisibility: .visible) {
            Button("破棄する", role: .destructive) { discard() }
            Button("編集を続ける", role: .cancel) {}
        } message: {
            Text("このテンプレートは作成されません。")
        }
        .onChange(of: focusedField) {
            commitDrafts()
        }
        .onAppear {
            if initialSnapshot == nil {
                initialSnapshot = TemplateSnapshot(template)
                nameDraft = template.name
                wakeUpDraft = template.wakeUpButtonText
            }
        }
        .onDisappear {
            // 画面が閉じきってから消す。表示中に消すと削除済みのモデルを参照してしまう。
            if isDiscarded {
                context.delete(template)
            } else {
                commitDrafts()
            }
        }
    }

    /// 入力中の文字をモデルに反映する。変わっていなければ書き込まない。
    private func commitDrafts() {
        if template.name != nameDraft { template.name = nameDraft }
        if template.wakeUpButtonText != wakeUpDraft { template.wakeUpButtonText = wakeUpDraft }
    }

    /// 何も変えていなければそのまま閉じ、変えていれば破棄してよいか確認する。
    private func cancelNew() {
        focusedField = nil
        commitDrafts()
        if TemplateSnapshot(template) == initialSnapshot {
            discard()
        } else {
            isDiscardConfirming = true
        }
    }

    private func discard() {
        isDiscarded = true
        dismiss()
    }

    @ViewBuilder
    private func alarmActions(hasAlarms: Bool) -> some View {
        Button("アラームを追加", systemImage: "plus.circle.fill") {
            focusedField = nil
            editing = .new
        }
        Button("時間帯でまとめて追加", systemImage: "list.bullet.indent") {
            focusedField = nil
            isBulkInputPresented = true
        }
        if hasAlarms {
            Button("ラベルをまとめて設定", systemImage: "tag") {
                focusedField = nil
                isBulkLabelPresented = true
            }
        }
        let others = templates.filter { $0 != template }
        if !others.isEmpty {
            Menu {
                ForEach(others) { other in
                    Button {
                        template.importAlarms(from: other)
                    } label: {
                        Text(other.name)
                        Text(other.enabledAlarmTimes)
                    }
                }
            } label: {
                Label("他のテンプレートから取り込む", systemImage: "square.and.arrow.down")
            }
            .simultaneousGesture(TapGesture().onEnded { focusedField = nil })
        }
    }
}

/// 新規作成中に変更があったかを比べるための、テンプレートの内容の写し。
private struct TemplateSnapshot: Equatable {
    struct Alarm: Equatable {
        let hour: Int
        let minute: Int
        let label: String
        let isEnabled: Bool
    }

    let name: String
    let colorName: String
    let wakeUpButtonText: String
    let alarms: [Alarm]

    init(_ template: AlarmTemplate) {
        name = template.name
        colorName = template.colorName
        wakeUpButtonText = template.wakeUpButtonText
        alarms = template.sortedAlarms.map { Alarm(hour: $0.hour, minute: $0.minute, label: $0.label, isEnabled: $0.isEnabled) }
    }
}

private struct AlarmRow: View {
    @Bindable var alarm: TemplateAlarm

    var body: some View {
        Toggle(isOn: $alarm.isEnabled) {
            AlarmTimeLabel(timeText: alarm.timeText, label: alarm.label, isEnabled: alarm.isEnabled)
        }
    }
}

private struct AlarmTimeLabel: View {
    let timeText: String
    let label: String
    let isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading) {
            Text(timeText)
                .font(.system(size: 36, weight: .light, design: .rounded))
                .monospacedDigit()
            if !label.isEmpty {
                Text(label)
                    .font(.caption)
            }
        }
        .foregroundStyle(isEnabled ? .primary : .secondary)
    }
}

/// 選択モードで使う、左に丸いチェックが付いた行。
/// onTapGesture ではなく Button にして、タップにすぐ反応するようにしている。
struct SelectableRow<Content: View>: View {
    let isSelected: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                content
                Spacer()
            }
            .contentShape(.rect)
        }
        .tint(.primary)
    }
}

/// 選択モードのとき、下のツールバーに「すべて選択」と「削除」を出す。削除の前に確認する。
/// 選択中はタブバーを隠して、ツールバーと重ならないようにする（写真アプリなどと同じ形）。
private struct SelectionDeleteBar: ViewModifier {
    let isSelecting: Bool
    @Binding var selection: Set<PersistentIdentifier>
    /// すべて選択を押したときだけ呼ぶ
    let allIDs: () -> [PersistentIdentifier]
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content
            .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
            .toolbar {
                if isSelecting {
                    ToolbarItem(placement: .bottomBar) {
                        Button(selection.isEmpty ? "すべて選択" : "選択解除") {
                            selection = selection.isEmpty ? Set(allIDs()) : []
                        }
                    }
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        DeleteSelectionButton(count: selection.count, onDelete: onDelete)
                    }
                }
            }
    }
}

/// 確認ダイアログをボタン自体に付けて、ボタンの位置から出す。
private struct DeleteSelectionButton: View {
    let count: Int
    let onDelete: () -> Void

    @State private var isConfirming = false

    var body: some View {
        Button(count == 0 ? "削除" : "\(count)件を削除", systemImage: "trash", role: .destructive) {
            isConfirming = true
        }
        .disabled(count == 0)
        .confirmationDialog("\(count)件のアラームを削除しますか？", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("削除", role: .destructive, action: onDelete)
        }
    }
}

extension View {
    func selectionDeleteBar(
        isSelecting: Bool,
        selection: Binding<Set<PersistentIdentifier>>,
        allIDs: @escaping () -> [PersistentIdentifier],
        onDelete: @escaping () -> Void
    ) -> some View {
        modifier(SelectionDeleteBar(isSelecting: isSelecting, selection: selection, allIDs: allIDs, onDelete: onDelete))
    }
}

enum AlarmEditTarget<Alarm: PersistentModel>: Identifiable {
    case new
    case existing(Alarm)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let alarm): "\(alarm.persistentModelID.hashValue)"
        }
    }
}

/// アラームの時刻とラベルを編集するシート。テンプレートのアラームと単発アラームで共用する。
struct AlarmEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let isNew: Bool
    let onSave: (_ hour: Int, _ minute: Int, _ label: String) -> Void

    @State private var time: Date
    @State private var label: String

    init(isNew: Bool, hour: Int = 7, minute: Int = 0, label: String = "", onSave: @escaping (_ hour: Int, _ minute: Int, _ label: String) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        _time = State(initialValue: Calendar.current.date(from: components) ?? .now)
        _label = State(initialValue: label)
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
                        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
                        onSave(components.hour ?? 0, components.minute ?? 0, label)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// アラームのラベルをまとめて設定するアラート。
private struct BulkLabelAlert: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let onApply: (_ label: String, _ onlyEmpty: Bool) -> Void

    @State private var label = ""

    func body(content: Content) -> some View {
        content.alert("ラベルをまとめて設定", isPresented: $isPresented) {
            TextField("ラベル", text: $label)
            Button("すべてに設定") { onApply(label, false) }
            Button("空欄のものだけに設定") { onApply(label, true) }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text(message + "空欄のまま「すべてに設定」するとラベルを消せます。")
        }
    }
}

extension View {
    func bulkLabelAlert(isPresented: Binding<Bool>, message: String, onApply: @escaping (_ label: String, _ onlyEmpty: Bool) -> Void) -> some View {
        modifier(BulkLabelAlert(isPresented: isPresented, message: message, onApply: onApply))
    }
}

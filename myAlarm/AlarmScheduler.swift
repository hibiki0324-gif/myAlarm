import AlarmKit
import AppIntents
import BackgroundTasks
import Foundation
import SwiftData
import SwiftUI

nonisolated struct ShiftAlarmMetadata: AlarmMetadata {}

/// 鳴っているアラームの「起きた」ボタンで実行され、そのアラームと、続けて鳴る予定のアラームを止める。
struct WakeUpIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "起きた"

    /// 鳴っているアラームの ID
    @Parameter(title: "アラーム ID")
    var alarmID: String

    init() {}

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        // ボタンの種類が .custom なので、iOS は鳴っているアラームを止めない。ここで止める。
        if let id = UUID(uuidString: alarmID) {
            try? AlarmManager.shared.stop(id: id)
        }
        await AlarmScheduler.shared.markAwake(from: .now)
        return .result()
    }
}

/// SwiftData の内容から今後のアラームを計算し、AlarmKit の登録内容と同期する。
/// 内容から決まる ID（PlannedAlarm.alarmID）で突き合わせ、不要になった分の取り消しと新しい分の登録だけを行う。
/// 「起きた」で止めた時刻（suppressedUntil）までのアラームは登録しない。
///
/// 同期のきっかけ:
/// - 登録すべき内容が変わったとき（ContentView の AlarmSyncObserver）。内容が前回と同じなら AlarmKit は呼ばない
/// - アプリがアクティブになったとき・バックグラウンド更新・「起きた」の操作。こちらは必ず AlarmKit と突き合わせる
@Observable
final class AlarmScheduler {
    static let shared = AlarmScheduler()
    static let refreshTaskID = "com.imamurahibiki.myAlarm.refresh"

    private(set) var authorizationState: AlarmManager.AuthorizationState = AlarmManager.shared.authorizationState
    private(set) var scheduledCount = 0
    private(set) var scheduledUntil: Date?
    private(set) var lastError: String?
    /// この時刻までのアラームは鳴らさない
    private(set) var suppressedUntil: Date? = UserDefaults.standard.object(forKey: suppressedUntilKey) as? Date

    private static let suppressedUntilKey = "suppressedUntil"
    private let manager = AlarmManager.shared
    private var debounceTask: Task<Void, Never>?
    private var isSyncing = false
    private var needsSync = false
    private var needsFullSync = false
    /// 前回の同期で登録した内容。内容が変わっていなければ AlarmKit を呼ばないために使う。
    private var lastSyncedIDs: Set<UUID>?

    /// now の時点で止めている範囲。過ぎていれば nil。
    func activeSuppression(at now: Date = .now) -> Date? {
        guard let suppressedUntil, suppressedUntil > now else { return nil }
        return suppressedUntil
    }

    /// anchor から続けて鳴る予定のアラームを止める。
    func markAwake(from anchor: Date) async {
        let alarms = upcomingPlans(from: .now).flatMap(\.alarms)
        setSuppressedUntil(AlarmPlanner.seriesEnd(from: anchor, in: alarms))
        await syncNow(full: true)
    }

    /// 止めていたアラームを元に戻す。
    func clearSuppression() async {
        setSuppressedUntil(nil)
        await syncNow(full: true)
    }

    private func setSuppressedUntil(_ date: Date?) {
        suppressedUntil = date
        UserDefaults.standard.set(date, forKey: Self.suppressedUntilKey)
    }

    private func upcomingPlans(from now: Date) -> [DayPlan] {
        let context = AppData.container.mainContext
        let templates = (try? context.fetch(FetchDescriptor<AlarmTemplate>())) ?? []
        let reservations = (try? context.fetch(FetchDescriptor<ShiftReservation>())) ?? []
        let oneOffs = (try? context.fetch(FetchDescriptor<OneOffAlarm>())) ?? []
        return AlarmPlanner.plans(
            days: AlarmPlanner.horizonDays,
            from: now,
            templates: templates,
            reservations: reservations,
            oneOffs: oneOffs
        )
    }

    /// 連続した変更をまとめるため、少し待ってから同期する。
    /// full が true なら、内容が前回と同じでも AlarmKit と突き合わせる。
    func requestSync(full: Bool = false) {
        needsFullSync = needsFullSync || full
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await syncNow()
        }
    }

    func syncNow(full: Bool = false) async {
        guard !DemoMode.isEnabled else { return }
        needsFullSync = needsFullSync || full
        needsSync = true
        guard !isSyncing else { return }
        isSyncing = true
        while needsSync {
            needsSync = false
            let full = needsFullSync
            needsFullSync = false
            await performSync(full: full)
        }
        isSyncing = false
    }

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = .now.addingTimeInterval(6 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        if manager.authorizationState == .notDetermined {
            _ = try? await manager.requestAuthorization()
        }
        let state = manager.authorizationState
        if authorizationState != state { authorizationState = state }
        return state == .authorized
    }

    private func performSync(full: Bool) async {
        guard await requestAuthorizationIfNeeded() else { return }

        let now = Date.now
        let plans = upcomingPlans(from: now)
        let notBefore = max(now, activeSuppression(at: now) ?? now)
        let desired = Dictionary(
            plans.flatMap(\.alarms).filter { $0.date > notBefore }.map { ($0.alarmID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let desiredIDs = Set(desired.keys)
        if !full, desiredIDs == lastSyncedIDs { return }

        do {
            let existing = try manager.alarms
            // 鳴っている最中のアラームは、ユーザーが止めるまでそのままにする
            for alarm in existing where desired[alarm.id] == nil && alarm.state != .alerting {
                try manager.cancel(id: alarm.id)
            }
            let existingIDs = Set(existing.map(\.id))
            for (id, planned) in desired where !existingIDs.contains(id) {
                _ = try await manager.schedule(id: id, configuration: configuration(for: planned, id: id))
            }
            lastSyncedIDs = desiredIDs
            // 値が同じなら書き込まない（書き込むと、表示している画面が描き直される）
            if scheduledCount != desired.count { scheduledCount = desired.count }
            if scheduledUntil != plans.last?.day { scheduledUntil = plans.last?.day }
            if lastError != nil { lastError = nil }
        } catch {
            lastSyncedIDs = nil
            lastError = error.localizedDescription
        }
    }

    private func configuration(for planned: PlannedAlarm, id: UUID) -> AlarmManager.AlarmConfiguration<ShiftAlarmMetadata> {
        let stopButton = AlarmButton(text: "停止", textColor: .white, systemImageName: "stop.circle")
        let wakeUpButton = AlarmButton(
            text: LocalizedStringResource(stringLiteral: planned.wakeUpButtonTitle),
            textColor: .white,
            systemImageName: "sun.max.fill"
        )
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: planned.title),
            stopButton: stopButton,
            secondaryButton: wakeUpButton,
            secondaryButtonBehavior: .custom
        )
        let attributes = AlarmAttributes<ShiftAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: planned.color.color
        )
        return .alarm(schedule: .fixed(planned.date), attributes: attributes, secondaryIntent: WakeUpIntent(alarmID: id))
    }
}

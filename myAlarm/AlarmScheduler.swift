import AlarmKit
import BackgroundTasks
import Foundation
import SwiftData
import SwiftUI

nonisolated struct ShiftAlarmMetadata: AlarmMetadata {}

/// SwiftData の内容から今後のアラームを計算し、AlarmKit の登録内容と同期する。
/// 同期のたびに既存のアラームをすべて取り消して登録し直す。
@Observable
final class AlarmScheduler {
    static let shared = AlarmScheduler()
    static let refreshTaskID = "com.imamurahibiki.myAlarm.refresh"

    private(set) var authorizationState: AlarmManager.AuthorizationState = AlarmManager.shared.authorizationState
    private(set) var scheduledCount = 0
    private(set) var scheduledUntil: Date?
    private(set) var lastError: String?

    private let manager = AlarmManager.shared
    private var container: ModelContainer?
    private var debounceTask: Task<Void, Never>?
    private var isSyncing = false
    private var needsSync = false

    func configure(container: ModelContainer) {
        self.container = container
    }

    /// 編集中の連続した変更をまとめるため、少し待ってから同期する。
    func requestSync() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            Task { await syncNow() }
        }
    }

    func syncNow() async {
        needsSync = true
        guard !isSyncing else { return }
        isSyncing = true
        while needsSync {
            needsSync = false
            await performSync()
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
        authorizationState = manager.authorizationState
        return authorizationState == .authorized
    }

    private func performSync() async {
        guard let context = container?.mainContext else { return }
        guard await requestAuthorizationIfNeeded() else { return }

        let now = Date.now
        let templates = (try? context.fetch(FetchDescriptor<AlarmTemplate>())) ?? []
        let reservations = (try? context.fetch(FetchDescriptor<ShiftReservation>())) ?? []
        let plans = AlarmPlanner.plans(days: AlarmPlanner.horizonDays, from: now, templates: templates, reservations: reservations)
        let upcoming = plans.flatMap(\.alarms).filter { $0.date > now }

        do {
            for alarm in try manager.alarms {
                try manager.cancel(id: alarm.id)
            }
            for planned in upcoming {
                _ = try await manager.schedule(id: UUID(), configuration: configuration(for: planned))
            }
            scheduledCount = upcoming.count
            scheduledUntil = plans.last?.day
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func configuration(for planned: PlannedAlarm) -> AlarmManager.AlarmConfiguration<ShiftAlarmMetadata> {
        let stopButton = AlarmButton(text: "停止", textColor: .white, systemImageName: "stop.circle")
        let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: planned.title), stopButton: stopButton)
        let attributes = AlarmAttributes<ShiftAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: planned.color.color
        )
        return .alarm(schedule: .fixed(planned.date), attributes: attributes)
    }
}

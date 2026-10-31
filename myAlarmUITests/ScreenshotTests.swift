import XCTest

/// App Store 用のスクリーンショットを撮る。fastlane snapshot から実行する。
@MainActor
final class ScreenshotTests: XCTestCase {
    private let timeout: TimeInterval = 10

    override func setUp() {
        continueAfterFailure = false
    }

    func testCaptureScreenshots() {
        let app = XCUIApplication()
        setupSnapshot(app, waitForAnimations: true)
        app.launchArguments += ["-demoMode"]
        app.launch()

        // 1. 予定
        XCTAssertTrue(app.buttons["day-12"].waitForExistence(timeout: timeout))
        snapshot("01_schedule")

        // 3. まとめて設定（パターン）
        app.buttons["まとめて設定"].firstMatch.tap()
        tap(app.buttons["月"])
        tap(app.buttons["パターン"])
        snapshot("03_bulk_pattern")
        tap(app.buttons["キャンセル"])

        // 5. 1 日の編集
        tap(app.buttons["day-12"])
        let section = app.staticTexts["テンプレートのアラーム"].firstMatch
        XCTAssertTrue(section.waitForExistence(timeout: timeout))
        // 勢いがつかないよう、押してからゆっくり動かす
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)))
        XCTAssertTrue(app.staticTexts["ごみ出し"].waitForExistence(timeout: timeout))
        snapshot("05_day_detail")
        tap(app.buttons["完了"])
        XCTAssertTrue(app.buttons["完了"].waitForNonExistence(timeout: timeout))

        // 2. テンプレート一覧
        tap(app.tabBars.buttons["テンプレート"])
        XCTAssertTrue(app.navigationBars["テンプレート"].waitForExistence(timeout: timeout))
        let dayShift = app.staticTexts["日勤"].firstMatch
        XCTAssertTrue(dayShift.waitForExistence(timeout: timeout))
        snapshot("02_templates")

        // 4. テンプレート編集
        dayShift.tap()
        XCTAssertTrue(app.navigationBars["日勤"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["最後の砦"].waitForExistence(timeout: timeout))
        snapshot("04_template_edit")
    }

    private func tap(_ query: XCUIElementQuery) {
        tap(query.firstMatch)
    }

    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(element) が見つかりません")
        element.tap()
    }
}

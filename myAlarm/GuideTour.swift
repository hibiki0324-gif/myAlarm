import SwiftUI
import TipKit

/// 予定タブの「?」から始めるガイドツアー。
/// 現在のステップ（GuideTour.step）に合う TourTip だけが表示される。
nonisolated enum GuideTour {
    /// 0 = ツアーなし。1 から順に進む。
    @Parameter static var step: Int = 0

    /// 各ステップの内容。順番がそのままツアーの順番になる。
    static let contents: [(title: String, message: String, symbol: String)] = [
        ("次のアラーム", "次に鳴るアラームです。下の「起きた」を押すと、続けて鳴る予定のアラームをまとめて止められます。", "alarm"),
        ("基本テンプレート", "日付を指定していない日に使うテンプレートです。ここで切り替えると、まとめて変わります。", "arrow.triangle.2.circlepath"),
        ("カレンダー", "日付をタップすると、その日だけテンプレートを変えたり、休みにしたり、この日だけのアラームを追加したりできます。", "calendar"),
        ("まとめて設定", "週・月・期間や曜日、繰り返しパターンで、テンプレートをまとめて設定できます。", "calendar.badge.plus"),
        ("テンプレート", "アラームのセットは下の「テンプレート」タブで作ります。アラームが鳴ったときは「起きた」で続くアラームをまとめて止められます。ツアーはこの「?」からいつでも見られます。", "questionmark.circle"),
    ]

    static var count: Int { contents.count }

    /// run はツアーを開始するたびに変わる番号。Tip の ID に含めて、前回閉じた Tip の記録を引き継がないようにする。
    static func tip(step: Int, run: Int) -> TourTip {
        let content = contents[step - 1]
        return TourTip(step: step, run: run, titleText: content.title, messageText: content.message, symbol: content.symbol)
    }
}

nonisolated struct TourTip: Tip {
    static let nextActionID = "next"
    static let endActionID = "end"

    let step: Int
    let run: Int
    let titleText: String
    let messageText: String
    let symbol: String

    var id: String { "guide-tour-\(run)-\(step)" }
    var title: Text { Text(titleText) }
    var message: Text? { Text(messageText) }
    var image: Image? { Image(systemName: symbol) }

    var rules: [Rule] {
        let step = step
        return [#Rule(GuideTour.$step) { $0 == step }]
    }

    var actions: [Action] {
        [
            Action(id: Self.endActionID, title: "ツアーを終了"),
            Action(id: Self.nextActionID, title: step == GuideTour.count ? "完了" : "次へ"),
        ]
    }
}

/// ツアー用の吹き出し。× ボタンは出さず、「ツアーを終了」と「次へ」を常に表示する。
struct TourTipStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        let step = (configuration.tip as? TourTip)?.step ?? 0
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                configuration.image?
                    .foregroundStyle(.tint)
                configuration.title?
                    .font(.headline)
                Spacer()
                Text("\(step)/\(GuideTour.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            configuration.message?
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                ForEach(configuration.actions) { action in
                    if action.id == TourTip.nextActionID {
                        Spacer()
                        Button(action: action.handler, label: action.label)
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button(action: action.handler, label: action.label)
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding()
    }
}

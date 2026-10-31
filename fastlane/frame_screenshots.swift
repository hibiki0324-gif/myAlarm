// 撮影した画像に背景とキャッチコピーを付け、透過なしの PNG で書き出す。
// 使い方: swift frame_screenshots.swift <入力フォルダ> <出力フォルダ>
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Slide {
    let key: String
    let headline: String
    let subhead: String
    let top: (CGFloat, CGFloat, CGFloat)
    let bottom: (CGFloat, CGFloat, CGFloat)
}

let slides = [
    Slide(key: "01_schedule", headline: "シフトが変わっても\nアラームは迷わない", subhead: "勤務予定をカレンダーで一目で確認", top: (0.15, 0.31, 0.78), bottom: (0.33, 0.20, 0.72)),
    Slide(key: "02_templates", headline: "日勤も夜勤も\nワンタップで切り替え", subhead: "アラームをテンプレートにまとめて管理", top: (0.93, 0.47, 0.13), bottom: (0.86, 0.25, 0.25)),
    Slide(key: "03_bulk_pattern", headline: "「日日夜夜休休」も\nまとめて登録", subhead: "週・月・期間に繰り返しパターンを設定", top: (0.27, 0.20, 0.68), bottom: (0.12, 0.13, 0.40)),
    Slide(key: "04_template_edit", headline: "二度寝を防ぐ連続アラームも\nセットで管理", subhead: "「起きた」でまとめて止められます", top: (0.05, 0.58, 0.58), bottom: (0.07, 0.36, 0.62)),
    Slide(key: "05_day_detail", headline: "この日だけの予定も\nかんたんに追加", subhead: "テンプレートとは別にアラームを設定", top: (0.84, 0.25, 0.47), bottom: (0.55, 0.20, 0.68)),
]

let canvasSize = CGSize(width: 1320, height: 2868)
let shotScale: CGFloat = 0.80
let shotTop: CGFloat = 520
let frameWidth: CGFloat = 16
let cornerRadius: CGFloat = 100

func drawCentered(_ text: String, font fontName: String, size: CGFloat, top: CGFloat, lineHeight: CGFloat, in context: CGContext) {
    let font = CTFontCreateWithName(fontName as CFString, size, nil)
    for (index, line) in text.components(separatedBy: "\n").enumerated() {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        ]
        let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attributes))
        let width = CTLineGetTypographicBounds(ctLine, nil, nil, nil)
        precondition(width <= canvasSize.width - 100, "文字が横幅を超えています: \(line)")
        context.textPosition = CGPoint(x: (canvasSize.width - width) / 2, y: canvasSize.height - top - lineHeight * CGFloat(index + 1))
        CTLineDraw(ctLine, context)
    }
}

func frame(_ slide: Slide, shot: CGImage) -> CGImage {
    guard let context = CGContext(
        data: nil, width: Int(canvasSize.width), height: Int(canvasSize.height),
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { fatalError("描画領域を作れませんでした") }

    let colors = [slide.top, slide.bottom].map { CGColor(red: $0.0, green: $0.1, blue: $0.2, alpha: 1) } as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: canvasSize.height), end: .zero, options: [])

    drawCentered(slide.headline, font: "HiraginoSans-W8", size: 88, top: 70, lineHeight: 130, in: context)
    drawCentered(slide.subhead, font: "HiraginoSans-W5", size: 50, top: 345, lineHeight: 70, in: context)

    let width = canvasSize.width * shotScale
    let height = width * CGFloat(shot.height) / CGFloat(shot.width)
    let rect = CGRect(x: (canvasSize.width - width) / 2, y: canvasSize.height - shotTop - height, width: width, height: height)
    let outer = rect.insetBy(dx: -frameWidth, dy: -frameWidth)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -24), blur: 70, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.4))
    context.setFillColor(CGColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1))
    context.addPath(CGPath(roundedRect: outer, cornerWidth: cornerRadius + frameWidth, cornerHeight: cornerRadius + frameWidth, transform: nil))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
    context.clip()
    context.interpolationQuality = .high
    context.draw(shot, in: rect)
    context.restoreGState()

    return context.makeImage()!
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else { fatalError("使い方: swift frame_screenshots.swift <入力フォルダ> <出力フォルダ>") }
let input = URL(fileURLWithPath: arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let files = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)

for slide in slides {
    guard let file = files.first(where: { $0.lastPathComponent.hasSuffix("\(slide.key).png") }),
          let source = CGImageSourceCreateWithURL(file as CFURL, nil),
          let shot = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fatalError("\(slide.key) の画像がありません") }

    let destination = output.appendingPathComponent("\(slide.key).png")
    guard let writer = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("\(destination.path) に書き出せません")
    }
    CGImageDestinationAddImage(writer, frame(slide, shot: shot), nil)
    guard CGImageDestinationFinalize(writer) else { fatalError("\(destination.path) に書き出せません") }
    print(destination.path)
}

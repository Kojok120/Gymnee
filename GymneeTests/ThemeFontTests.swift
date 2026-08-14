import XCTest
import UIKit
@testable import Gymnee

/// バンドルしているドットフォントが実際に使えるかの検証。
///
/// SwiftUI の `Font.custom` は名前を間違えても**エラーにならず黙ってシステムフォントで描く**ので、
/// Info.plist の UIAppFonts 漏れ・ファイル名変更・PostScript 名の取り違えは
/// 画面を見るまで気づけない。ここで機械的に止める。
final class ThemeFontTests: XCTestCase {

    /// PostScript 名でフォントが解決できる（＝登録も同梱もできている）。
    func testPixelFontIsRegistered() {
        let font = UIFont(name: Theme.pixelFontName, size: 16)
        XCTAssertNotNil(font, "\(Theme.pixelFontName) を解決できない。Info.plist の UIAppFonts と同梱を確認する")
        XCTAssertEqual(font?.fontName, Theme.pixelFontName)
    }

    /// 同梱されているファイル自体が読める。
    func testPixelFontFileIsBundled() {
        let url = Bundle(for: Self.self).url(forResource: "DotGothic16-Regular", withExtension: "ttf")
            ?? Bundle.main.url(forResource: "DotGothic16-Regular", withExtension: "ttf")
        XCTAssertNotNil(url, "DotGothic16-Regular.ttf が同梱されていない")
    }

    /// 日本語（手紙・ふきだしで実際に出る文字）がフォント側にある。
    /// 欠けているとその字だけシステムフォントに落ちて、ドット絵の中で浮く。
    func testPixelFontCoversJapaneseUsedInRoom() throws {
        let font = try XCTUnwrap(UIFont(name: Theme.pixelFontName, size: 16))
        let set = CTFontCopyCharacterSet(font) as CharacterSet
        // 置き手紙・ふきだしの定型文で使う字（漢字・かな・記号・数字）。
        for scalar in "「朝の丘」でいいものを探してきます。帰りはあと29分。今週はあと3回、まだ間に合う".unicodeScalars {
            XCTAssertTrue(set.contains(scalar), "\(scalar) がドットフォントに無い")
        }
    }
}

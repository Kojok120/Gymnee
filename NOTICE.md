# サードパーティのライセンス表示

Gymnee には以下のオープンソース成果物を取り込んでいます。

## MuscleMap

分析タブの人体図（正面・背面）の解剖パスと、それを描くための SVG パーサーに使用しています。

- 出典: https://github.com/melihcolpan/MuscleMap
- 作者: Melih Colpan
- ライセンス: MIT License

取り込んだファイル:

- `Gymnee/Features/Analytics/BodyMap/BodyMapArtwork.swift`
  （MuscleMap の male front / back のパスデータ。Gymnee の `MuscleGroup` へマッピングし直しただけで、図形自体は改変していない。親と重なるサブグループは取り込んでいない）
- `Gymnee/Features/Analytics/BodyMap/SVGPathParser.swift`（MuscleMap の `Core/SVGPathParser.swift`）
- `Gymnee/Features/Analytics/BodyMap/SVGPathBuilder.swift`（MuscleMap の `Core/SVGPathCommand.swift` と `Core/PathBuilder.swift` を1ファイルにまとめたもの）

### ライセンス全文

```
MIT License

Copyright (c) 2026 Melih Colpan

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

"""LINE のリッチメニューの画像（2500×843、4 つのボタン）を作る。

  python3 connect/scripts/make-richmenu-image.py

出力: connect/assets/richmenu.png（line-setup.mjs が読む）。文言を変えたら作り直す。
配色はサイトと同じ（黒地・ライム）。ボタンの並びは line-setup.mjs の areas と同じ順にする。
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

W, H = 2500, 843
BG = (11, 13, 12)
CARD = (24, 27, 23)
LIME = (198, 255, 61)
TEXT = (244, 247, 242)
MUTED = (167, 174, 166)
BOLD = "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc"
REGULAR = "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc"

BUTTONS = [
    ("今日のメニュー", "コーチが組む"),
    ("記録する", "送るだけで記録"),
    ("ふりかえり", "今週の回数と総量"),
    ("相談する", "痛み・時間・やる気"),
]


def icon(draw: ImageDraw.ImageDraw, kind: int, cx: int, cy: int) -> None:
    """ボタンごとの簡単な図形（外部の素材を使わない）。"""
    s = 70
    if kind == 0:  # ダンベル
        draw.rounded_rectangle((cx - s, cy - 14, cx + s, cy + 14), radius=10, fill=LIME)
        for dx in (-s, s):
            draw.rounded_rectangle((cx + dx - 26, cy - 48, cx + dx + 26, cy + 48), radius=12, fill=LIME)
    elif kind == 1:  # ペン（記録）
        draw.rounded_rectangle((cx - 60, cy - 50, cx + 60, cy + 50), radius=16, outline=LIME, width=12)
        draw.line((cx - 30, cy, cx - 6, cy + 24, cx + 36, cy - 22), fill=LIME, width=14, joint="curve")
    elif kind == 2:  # 棒グラフ
        for i, h in enumerate((40, 70, 100)):
            x = cx - 66 + i * 50
            draw.rounded_rectangle((x, cy + 50 - h, x + 34, cy + 50), radius=8, fill=LIME)
    else:  # 吹き出し
        draw.rounded_rectangle((cx - 70, cy - 52, cx + 70, cy + 34), radius=28, fill=LIME)
        draw.polygon([(cx - 30, cy + 30), (cx - 52, cy + 62), (cx - 2, cy + 30)], fill=LIME)


def main() -> None:
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)
    title = ImageFont.truetype(BOLD, 92)
    sub = ImageFont.truetype(REGULAR, 54)
    col = W // 4
    for i, (label, caption) in enumerate(BUTTONS):
        x0 = i * col + 18
        draw.rounded_rectangle((x0, 18, x0 + col - 36, H - 18), radius=48, fill=CARD)
        cx = i * col + col // 2
        icon(draw, i, cx, 250)
        # 長いラベルは枠に収まるまで縮める（はみ出させない）。
        size = 92
        font = title
        while draw.textlength(label, font=font) > col - 140 and size > 48:
            size -= 4
            font = ImageFont.truetype(BOLD, size)
        tw = draw.textlength(label, font=font)
        draw.text((cx - tw / 2, 430 + (92 - size) // 2), label, font=font, fill=TEXT)
        sw = draw.textlength(caption, font=sub)
        draw.text((cx - sw / 2, 580), caption, font=sub, fill=MUTED)
    out = Path(__file__).resolve().parent.parent / "assets" / "richmenu.png"
    img.save(out, optimize=True)
    print(out, out.stat().st_size)


if __name__ == "__main__":
    main()

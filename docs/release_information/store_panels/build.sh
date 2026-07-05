#!/bin/bash
# App Store スクリーンショットパネルの一括ビルド。
# template.html（PANELS 定義）を編集 → このスクリプトを再実行すれば全パネルを再生成できる。
#
#   使い方: bash docs/release_information/store_panels/build.sh
#
# 出力:
#   docs/release_information/screenshots/         6.9インチ 1320×2868 × 8枚
#   docs/release_information/screenshots_6.5inch/ 6.5インチ 1284×2778 × 8枚（6.9マスターの縮小＋中央クロップ）
#
# 注意: screens/10-ai-plan-raw.png（TestFlight 表示入り）は存在しても使用禁止。
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
OUT69="$DIR/../screenshots"
OUT65="$DIR/../screenshots_6.5inch"
MAGICK="/opt/homebrew/bin/magick"
TMP="$(mktemp -d)"

# パネル順とファイル名（App Store の表示順 = ファイル名順を想定）
NAMES=(01-record 02-ai-plan 03-home-calendar 04-analytics 05-checkin 06-social 07-achievements 08-share)

# レンダラーは Playwright 同梱の Chromium（初回のみ `npx -y playwright install chromium`）。
# Chrome.app のバイナリ直接起動は、本体 Chrome が起動中だと競合してハングするため使わない。
render() { # $1=hash $2=width $3=out
  npx -y playwright screenshot --browser chromium \
    --viewport-size "$2,2868" \
    --wait-for-timeout 4000 \
    "file://$DIR/template.html#$1" "$3" >/dev/null 2>&1
}

rm -rf "$OUT69" "$OUT65"
mkdir -p "$OUT69" "$OUT65"

# 1〜2枚目: パノラマ（2640px）でレンダー → 左右分割
echo "render #pano (panels 01-02)"
render pano 2640 "$TMP/pano.png"
"$MAGICK" "$TMP/pano.png" -crop 1320x2868+0+0 +repage "$OUT69/${NAMES[0]}.png"
"$MAGICK" "$TMP/pano.png" -crop 1320x2868+1320+0 +repage "$OUT69/${NAMES[1]}.png"

# 3〜8枚目: 個別レンダー
for i in 3 4 5 6 7 8; do
  hash=$(printf "%02d" "$i")
  name="${NAMES[$((i-1))]}"
  echo "render #$hash -> $name"
  render "$hash" 1320 "$OUT69/$name.png"
done

# 6.5インチ版: 6.9 マスターを縮小（1284幅）→ 中央クロップ（上下6pxずつ）
for name in "${NAMES[@]}"; do
  cp "$OUT69/$name.png" "$OUT65/$name.png"
  sips --resampleWidth 1284 "$OUT65/$name.png" >/dev/null
  sips -c 2778 1284 "$OUT65/$name.png" >/dev/null
done

# 寸法検証（規定サイズ以外が混ざったら失敗させる）
fail=0
for name in "${NAMES[@]}"; do
  s69=$(sips -g pixelWidth -g pixelHeight "$OUT69/$name.png" | awk '/pixel/{printf "%sx", $2}' | sed 's/x$//')
  s65=$(sips -g pixelWidth -g pixelHeight "$OUT65/$name.png" | awk '/pixel/{printf "%sx", $2}' | sed 's/x$//')
  [ "$s69" = "1320x2868" ] || { echo "NG 6.9: $name = $s69"; fail=1; }
  [ "$s65" = "1284x2778" ] || { echo "NG 6.5: $name = $s65"; fail=1; }
done
rm -rf "$TMP"
[ "$fail" -eq 0 ] && echo "OK: 8 panels x 2 sizes generated" || exit 1

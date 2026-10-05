#!/bin/bash
# ストア画像の素材（キャラ・ボス・ペット）を、DEBUG 画面のスクショから1体ずつ切り出す（issue #135）。
#
# 1. シミュレータ（iPhone 16 Pro Max・@3x）で次の3枚を撮り、このディレクトリに sheet0〜2.png として置く
#      xcrun simctl launch <id> com.gymnee.app.dev -gymneeDemo -gymneeScreen promo-sheet-<0|1|2>
#      xcrun simctl io <id> screenshot sheet<0|1|2>.png
# 2. bash build_sprites.sh → sprites/*.png（背景を抜いて余白を詰めた透過 PNG）
#
# 格子は PromoArtSheet と同じ: 2列×4段、1マス 210×215pt、原点 (10 + 列×215, 66 + 段×220)pt。
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
MAGICK="/opt/homebrew/bin/magick"
mkdir -p "$DIR/sprites"
NAMES0=(hero-crown hero-ponytail hero-headband hero-shades hero-long hero-glasses hero-cap hero-earphones)
NAMES1=(boss-sloth_slime-strong boss-couch_golem-strong boss-snooze_dragon-strong boss-junk_kraken-strong
        boss-sloth_slime-medium boss-couch_golem-medium boss-snooze_dragon-medium boss-junk_kraken-medium)
NAMES2=(boss-sloth_slime-weak boss-couch_golem-weak boss-snooze_dragon-weak boss-junk_kraken-weak
        pet-shiba pet-tabby coach hero-plain)
cut() { # $1=sheet $2=index $3=name
  local col=$(( $2 % 2 )) row=$(( $2 / 2 ))
  local x=$(( (10 + col * 215) * 3 )) y=$(( (66 + row * 220) * 3 ))
  "$MAGICK" "$DIR/$1" -crop 630x645+${x}+${y} +repage \
    -fuzz 38% -transparent "#FF00FF" -trim +repage "$DIR/sprites/$3.png"
}
for i in "${!NAMES0[@]}"; do cut sheet0.png "$i" "${NAMES0[$i]}"; done
for i in "${!NAMES1[@]}"; do cut sheet1.png "$i" "${NAMES1[$i]}"; done
for i in "${!NAMES2[@]}"; do cut sheet2.png "$i" "${NAMES2[$i]}"; done
echo "sprites: $(ls "$DIR/sprites" | wc -l | tr -d ' ')"

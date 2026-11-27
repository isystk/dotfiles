#!/bin/bash
# infographic.html を PNG に書き出す（Playwright の公式 Docker イメージを使う。プロジェクトの環境に依存しない）
# 使い方: render.sh <HTMLのあるフォルダ> [出力PNG名]
#   例: render.sh tmp/login-fix login-fix_インフォグラフィック.png
# 環境変数:
#   PLAYWRIGHT_IMAGE / PLAYWRIGHT_VERSION  イメージと、npm の playwright のバージョン（両方そろえる）
#   JP_FONT_REGULAR / JP_FONT_BOLD         日本語フォントのパス（未指定なら自動で探す。Bold が無ければ Regular で代用）
set -euo pipefail

DIR=${1:?"HTML のあるフォルダを指定してください"}
OUT=${2:-infographic.png}
IMAGE=${PLAYWRIGHT_IMAGE:-mcr.microsoft.com/playwright:v1.64.1-noble}
PW_VERSION=${PLAYWRIGHT_VERSION:-1.64.1}
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FONT_DIRS=(/usr/share/fonts /usr/local/share/fonts "$HOME/.fonts" "$HOME/.local/share/fonts" "$HOME/Library/Fonts" /Library/Fonts)

[ -f "$DIR/infographic.html" ] || { echo "$DIR/infographic.html がありません" >&2; exit 1; }
DIR=$(cd "$DIR" && pwd)
command -v docker >/dev/null || { echo "docker が使えません" >&2; exit 1; }

# 日本語フォントの候補を優先順に出す（Noto Sans CJK の定位置 → 各フォント置き場の Noto Sans CJK/JP → fc-list の日本語フォント）
font_candidates() {
  local w=$1 d
  printf '%s\n' \
    "/usr/share/fonts/opentype/noto/NotoSansCJK-$w.ttc" \
    "/usr/share/fonts/noto-cjk/NotoSansCJK-$w.ttc" \
    "/usr/share/fonts/google-noto-cjk/NotoSansCJK-$w.ttc" \
    "/usr/share/fonts/truetype/noto/NotoSansCJK-$w.ttc"
  for d in "${FONT_DIRS[@]}"; do
    [ -d "$d" ] && { find "$d" -type f \( -iname 'NotoSansCJK*' -o -iname 'NotoSansJP*' \) 2>/dev/null | sort || true; }
  done
  if command -v fc-list >/dev/null; then
    fc-list :lang=ja file 2>/dev/null | sed 's/:[[:space:]]*$//' | sort || true
  fi
}

# $1: Regular か Bold。見つかったパスを1つ出す（無ければ何も出さない）
find_font() {
  local w=$1 f name
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    name=$(basename "$f" | tr '[:upper:]' '[:lower:]')
    if [ "$w" = Bold ]; then
      case $name in *bold*) echo "$f"; return 0 ;; esac
    else
      case $name in *bold*|*black*|*thin*|*light*|*medium*|*demi*) continue ;; esac
      echo "$f"; return 0
    fi
  done < <(font_candidates "$w")
  return 0
}

REG=${JP_FONT_REGULAR:-$(find_font Regular)}
if [ -z "$REG" ] || [ ! -f "$REG" ]; then
  {
    echo "日本語フォントが見つかりません。探した場所: ${FONT_DIRS[*]} と fc-list"
    echo "Noto Sans CJK を入れる（例: sudo apt install fonts-noto-cjk）か、JP_FONT_REGULAR=<フォントのパス> を指定してください"
  } >&2
  exit 1
fi
BOLD=${JP_FONT_BOLD:-$(find_font Bold)}
{ [ -n "$BOLD" ] && [ -f "$BOLD" ]; } || BOLD=$REG

# フォントは読み取り専用でコンテナの /fonts に渡し（コンテナには日本語フォントが無いため）、@font-face を fonts.css に書く
FONT_MOUNTS=(-v "$REG:/fonts/jp-regular.${REG##*.}:ro")
FACE_R="/fonts/jp-regular.${REG##*.}"
FACE_B=$FACE_R
if [ "$BOLD" != "$REG" ]; then
  FONT_MOUNTS+=(-v "$BOLD:/fonts/jp-bold.${BOLD##*.}:ro")
  FACE_B="/fonts/jp-bold.${BOLD##*.}"
fi
cat > "$DIR/fonts.css" <<EOF
@font-face { font-family:"NotoJP"; src:url("$FACE_R"); font-weight:400; }
@font-face { font-family:"NotoJP"; src:url("$FACE_B"); font-weight:700; }
EOF
echo "日本語フォント: $REG (Bold: $BOLD)"

# playwright の npm パッケージは、コンテナ内の /tmp に入れる（初回はダウンロードが走る）
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e OUT_NAME="$OUT" \
  -v "$DIR:/work" "${FONT_MOUNTS[@]}" -v "$SCRIPT_DIR/render.cjs:/render/render.cjs:ro" \
  "$IMAGE" sh -c "cd /tmp && npm init -y >/dev/null && npm i playwright@$PW_VERSION --no-audit --no-fund --loglevel=error >/dev/null && NODE_PATH=/tmp/node_modules node /render/render.cjs"

echo "出力: $DIR/$OUT"

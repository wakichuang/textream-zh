#!/bin/bash
# 中文排版回歸檢查：切字、每行實際寬度是否超出容器、畫出 PNG。
# 只需要 Command Line Tools（不需要 Xcode）。用法：zh/verify-layout/run.sh [輸出資料夾]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../../Textream/Textream"
OUT="${1:-$(mktemp -d)}"
mkdir -p "$OUT"
WORK="$(mktemp -d)"
python3 "$HERE/extract.py" "$SRC/MarqueeTextView.swift" "$WORK/layout.swift"
swiftc -O "$HERE/main.swift" "$WORK/layout.swift" "$SRC/SpeechTextAlignment.swift" "$SRC/TextDirection.swift" -o "$WORK/run"
"$WORK/run" 目前版本 "$OUT"
echo "圖片：$OUT"

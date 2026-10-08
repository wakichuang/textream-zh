#!/bin/bash
# 中文比對回歸檢查：原版與新版比對各跑一次 ZH-01～ZH-23、原版移植測試、Mac 專屬情境與數字正規化。
# 不需要開 Xcode。用法：zh/verify-matcher/run.sh；新版有任何一條沒過，結束碼為 1。
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../../Textream/Textream"
WORK="$(mktemp -d)"
# 斷字（splitTextIntoWords）在 MarqueeTextView.swift 的開頭，只抽那一段，避開 SwiftUI
python3 - "$SRC/MarqueeTextView.swift" "$WORK/tokenizer.swift" <<'PY'
import sys
lines = open(sys.argv[1], encoding='utf-8').read().split('\n')
end = next(i for i, l in enumerate(lines) if l.startswith('// MARK: - Data'))
open(sys.argv[2], 'w', encoding='utf-8').write('\n'.join(lines[:end]).replace('import SwiftUI', 'import AppKit'))
PY
python3 "$HERE/make_legacy.py" "$SRC/SpeechRecognizer.swift" "$WORK/legacy.swift"
swiftc -O "$HERE/main.swift" "$WORK/tokenizer.swift" "$WORK/legacy.swift" \
  "$SRC/SpeechTextAlignment.swift" "$SRC"/ZhMatching/*.swift -o "$WORK/run"
"$WORK/run" "$SRC/ZhMatching/unihan-pinyin.tsv"

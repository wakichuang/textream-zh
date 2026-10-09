#!/bin/bash
# 編輯模式與播放模式的位置互換（EditorPlaybackPosition.swift）回歸檢查。只需要 Command Line Tools。
# 用法：zh/verify-position/run.sh [來源資料夾]；有任何一條沒過，結束碼為 1。
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-$HERE/../../Textream/Textream}"
WORK="$(mktemp -d)"
# 切字（splitTextIntoWords）在 MarqueeTextView.swift 的開頭，只抽那一段，避開 SwiftUI
python3 - "$HERE/../../Textream/Textream/MarqueeTextView.swift" "$WORK/tokenizer.swift" <<'PY'
import sys
lines = open(sys.argv[1], encoding='utf-8').read().split('\n')
end = next(i for i, l in enumerate(lines) if l.startswith('// MARK: - Data'))
open(sys.argv[2], 'w', encoding='utf-8').write('\n'.join(lines[:end]).replace('import SwiftUI', 'import AppKit'))
PY
swiftc -O "$HERE/main.swift" "$WORK/tokenizer.swift" "$SRC/EditorPlaybackPosition.swift" -o "$WORK/run"
"$WORK/run"

#!/bin/bash
# 滾輪逐行跳轉回歸檢查（WheelLineJump.swift）。只需要 Command Line Tools。
# 用法：zh/verify-scroll/run.sh [來源資料夾]；有任何一條沒過，結束碼為 1。
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-$HERE/../../Textream/Textream}"
WORK="$(mktemp -d)"
swiftc -O "$HERE/main.swift" "$SRC/WheelLineJump.swift" -o "$WORK/run"
"$WORK/run"

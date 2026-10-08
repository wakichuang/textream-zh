#!/bin/bash
# 編譯 Textream 繁中改版、用 Apple Development 憑證簽名、裝到 /Applications。
# 用法：zh/install.sh
# 需要：Xcode、在 Xcode → Settings → Accounts 登入過 Apple ID（免費帳號即可）。
#
# 為什麼自己簽名：macOS 的麥克風與語音辨識權限綁在簽名上。用固定的開發者憑證簽，
# 重新編譯後權限照舊；不簽或臨時簽名，每次重編都可能被當成新的 App。
# 為什麼不用 Xcode 的自動簽名：識別碼 dev.fka.textream 已登記在原作者的團隊底下，
# 自動簽名會註冊失敗。這幾項權限（沙盒、麥克風、網路）在 macOS 不需要描述檔，直接簽即可。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$HERE/../Textream"
BUILD_DIR="$HERE/../build/zh-install"   # build/ 已在 .gitignore
APP_NAME="Textream.app"
DEST="/Applications/$APP_NAME"
BUNDLE_ID="dev.fka.textream"

IDENTITY="${SIGNING_IDENTITY:-$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)}"
if [ -z "$IDENTITY" ]; then
  echo "找不到 Apple Development 憑證。請打開 Xcode → Settings → Accounts 登入 Apple ID，"
  echo "選你的 Personal Team → Manage Certificates → 左下角 + → Apple Development。"
  exit 1
fi
echo "憑證：$IDENTITY"

echo "編譯中（Release、Apple Silicon）…"
xcodebuild build \
  -project "$PROJECT_DIR/Textream.xcodeproj" \
  -scheme Textream \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

APP="$BUILD_DIR/Build/Products/Release/$APP_NAME"

echo "簽名中…"
codesign --force --sign "$IDENTITY" \
  --entitlements "$PROJECT_DIR/Textream/Textream.entitlements" \
  --timestamp=none \
  "$APP"
codesign --verify --strict "$APP"

if pgrep -xq Textream; then
  echo "關閉執行中的 Textream…"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" || true
  for _ in $(seq 1 20); do pgrep -xq Textream || break; sleep 0.5; done
fi

if [ -e "$DEST" ]; then
  echo "舊版移到垃圾桶：$DEST"
  trash "$DEST"
fi
ditto "$APP" "$DEST"

echo "安裝完成：$DEST"
codesign -dv "$DEST" 2>&1 | grep -E '^(Identifier|Authority)=' | head -2
open "$DEST"
